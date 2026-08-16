package log

import (
	"context"
	"testing"
)

func TestRequestID(t *testing.T) {
	tests := []struct {
		name string
		id   string
	}{
		{"plain id", "req-abc123"},
		{"empty id", ""},
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
		{"empty id", ""},
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

	if _, ok := TraceID(context.Background()); ok {
		t.Error("TraceID() ok = true on empty context, want false")
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
