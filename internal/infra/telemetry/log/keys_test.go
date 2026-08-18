package log

import (
	"context"
	"strings"
	"testing"
)

func TestRequestID(t *testing.T) {
	tests := []struct {
		name string
		id   string
	}{
		{"plain id", "req-abc123"},
		{"max length", strings.Repeat("a", maxCorrelationIDLen)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := WithRequestID(context.Background(), tt.id)
			got, ok := RequestID(ctx)
			if !ok {
				t.Fatal("RequestID() ok = false, want true")
			}
			if got != tt.id {
				t.Errorf("RequestID() = %q, want %q", got, tt.id)
			}
		})
	}

	// Empty-string = absent (package policy): the setter stores nothing, the
	// getter reports absent. Empty/over-long/control-char rejection is
	// exercised in TestCorrelationIDBounds.
	if _, ok := RequestID(context.Background()); ok {
		t.Error("RequestID() ok = true on empty context, want false")
	}
}

func TestSubjectID(t *testing.T) {
	tests := []struct {
		name string
		id   int64
	}{
		{"positive", 42},
		{"zero", 0},
		{"max int64", 1<<63 - 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := WithSubjectID(context.Background(), tt.id)
			got, ok := SubjectID(ctx)
			if !ok {
				t.Fatal("SubjectID() ok = false, want true")
			}
			if got != tt.id {
				t.Errorf("SubjectID() = %d, want %d", got, tt.id)
			}
		})
	}

	if _, ok := SubjectID(context.Background()); ok {
		t.Error("SubjectID() ok = true on empty context, want false")
	}
}

func TestTraceID(t *testing.T) {
	tests := []struct {
		name string
		id   string
	}{
		{"plain id", "trace-xyz789"},
		{"max length", strings.Repeat("b", maxCorrelationIDLen)},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctx := WithTraceID(context.Background(), tt.id)
			got, ok := TraceID(ctx)
			if !ok {
				t.Fatal("TraceID() ok = false, want true")
			}
			if got != tt.id {
				t.Errorf("TraceID() = %q, want %q", got, tt.id)
			}
		})
	}

	// Empty-string = absent (package policy): nothing stored, so the
	// decorator's extractor fallback can run (tested in
	// context_handler_test.go).
	if _, ok := TraceID(context.Background()); ok {
		t.Error("TraceID() ok = true on empty context, want false")
	}
}

// TestCorrelationIDBounds drives both string setters with out-of-bounds
// values: empty, over-length, and control-char ids must leave
// ctx unchanged (nothing stored), so the decorator can never emit them.
// subject_id (int64) is untouched by this validation.
func TestCorrelationIDBounds(t *testing.T) {
	invalid := []struct {
		name string
		id   string
	}{
		{"empty", ""},
		{"over-long", strings.Repeat("a", maxCorrelationIDLen+1)},
		{"over-long multi-byte", strings.Repeat("€", maxCorrelationIDLen)}, // 128 runes = 384 bytes
		{"control char", "req\x1b[31mred\x1b[0m"},
		{"c1 control char", "req\u009b[7m"},
		{"del char", "req\x7f"},
	}
	sets := []struct {
		name string
		set  func(context.Context, string) context.Context
	}{
		{"request_id", WithRequestID},
		{"trace_id", WithTraceID},
	}
	for _, s := range sets {
		for _, tt := range invalid {
			t.Run(s.name+"/"+tt.name, func(t *testing.T) {
				base := context.Background()
				if got := s.set(base, tt.id); got != base {
					t.Error("setter returned a different context for invalid id — nothing must be stored")
				}
				if s.name == "request_id" {
					if _, ok := RequestID(base); ok {
						t.Error("RequestID() ok = true after invalid set, want false")
					}
				} else {
					if _, ok := TraceID(base); ok {
						t.Error("TraceID() ok = true after invalid set, want false")
					}
				}
			})
		}
	}

	// Boundary: exactly maxCorrelationIDLen bytes is still a valid id for
	// both setters.
	if _, ok := RequestID(WithRequestID(context.Background(), strings.Repeat("a", maxCorrelationIDLen))); !ok {
		t.Error("max-length request id dropped by setter, want stored")
	}
	if _, ok := TraceID(WithTraceID(context.Background(), strings.Repeat("b", maxCorrelationIDLen))); !ok {
		t.Error("max-length trace id dropped by setter, want stored")
	}
}

// TestNilContextSafety pins the nil-ctx contract: every setter/getter
// treats a nil ctx as context.Background(), so middleware chains over a
// possibly-nil ctx never panic (the decorator is already nil-safe).
//
//nolint:staticcheck // SA1012: nil contexts here are the contract under test, not accidental.
func TestNilContextSafety(t *testing.T) {
	ctx := WithRequestID(WithSubjectID(WithTraceID(nil, "trace-1"), 42), "req-1")
	if ctx == nil {
		t.Fatal("setter chain returned a nil context for nil input")
	}
	if id, ok := RequestID(ctx); !ok || id != "req-1" {
		t.Errorf("RequestID() after nil chain = %q, %v; want %q, true", id, ok, "req-1")
	}
	if id, ok := SubjectID(ctx); !ok || id != 42 {
		t.Errorf("SubjectID() after nil chain = %d, %v; want 42, true", id, ok)
	}
	if id, ok := TraceID(ctx); !ok || id != "trace-1" {
		t.Errorf("TraceID() after nil chain = %q, %v; want %q, true", id, ok, "trace-1")
	}

	if _, ok := RequestID(nil); ok {
		t.Error("RequestID(nil) ok = true, want false")
	}
	if _, ok := SubjectID(nil); ok {
		t.Error("SubjectID(nil) ok = true, want false")
	}
	if _, ok := TraceID(nil); ok {
		t.Error("TraceID(nil) ok = true, want false")
	}
}

// TestKeysAreIndependent guards the distinct-key-type design: setting one
// field must never make another field readable, and values must survive
// context nesting.
func TestKeysAreIndependent(t *testing.T) {
	ctx := WithRequestID(
		WithSubjectID(context.Background(), 7),
		"req-1",
	)

	if id, ok := RequestID(ctx); !ok || id != "req-1" {
		t.Errorf("RequestID() = %q, %v; want %q, true", id, ok, "req-1")
	}
	if id, ok := SubjectID(ctx); !ok || id != 7 {
		t.Errorf("SubjectID() = %d, %v; want %d, true", id, ok, 7)
	}
	if _, ok := TraceID(ctx); ok {
		t.Error("TraceID() ok = true on context without trace id, want false")
	}

	// Absent values must stay absent through nested contexts too.
	child := WithTraceID(ctx, "trace-1")
	if _, ok := TraceID(child); !ok {
		t.Fatal("TraceID() ok = false after WithTraceID, want true")
	}
}
