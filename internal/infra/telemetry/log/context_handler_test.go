package log

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"strings"
	"testing"
	"testing/slogtest"
	"time"
)

// captureJSON returns a JSON logger built on a context-decorated handler
// (bytes.Buffer + NewHandler(FormatJSON) + NewContextHandler) writing into
// buf.
func captureJSON(opts ContextHandlerOptions) (*bytes.Buffer, *slog.Logger) {
	var buf bytes.Buffer
	logger := slog.New(NewContextHandler(NewHandler(slog.LevelDebug, FormatJSON, &buf), opts))
	return &buf, logger
}

// parseLines parses each non-empty JSON line of src into a map.
func parseLines(t *testing.T, src []byte) []map[string]any {
	t.Helper()
	var ms []map[string]any
	for _, line := range bytes.Split(src, []byte{'\n'}) {
		if len(bytes.TrimSpace(line)) == 0 {
			continue
		}
		var m map[string]any
		if err := json.Unmarshal(line, &m); err != nil {
			t.Fatalf("invalid JSON line %q: %v", line, err)
		}
		ms = append(ms, m)
	}
	return ms
}

// correlationCtx returns a context carrying all three correlation fields.
func correlationCtx() context.Context {
	return WithSubjectID(WithTraceID(WithRequestID(context.Background(), "req-123"), "trace-abc"), 42)
}

// TestContextHandlerInjectionTable drives the inject/omit matrix: fields
// present in ctx are injected with their exact values, absent fields are
// omitted entirely (the emitted line lacks the key, not just the value).
func TestContextHandlerInjectionTable(t *testing.T) {
	tests := []struct {
		name       string
		ctx        context.Context
		extractor  func(context.Context) string
		wantKeys   map[string]any
		absentKeys []string
	}{
		{
			name:     "all three present",
			ctx:      correlationCtx(),
			wantKeys: map[string]any{requestIDAttr: "req-123", subjectIDAttr: float64(42), traceIDAttr: "trace-abc"},
		},
		{
			name:       "none present",
			ctx:        context.Background(),
			absentKeys: []string{requestIDAttr, subjectIDAttr, traceIDAttr},
		},
		{
			name:       "request and subject only",
			ctx:        WithSubjectID(WithRequestID(context.Background(), "req-1"), 7),
			wantKeys:   map[string]any{requestIDAttr: "req-1", subjectIDAttr: float64(7)},
			absentKeys: []string{traceIDAttr},
		},
		{
			name:       "empty trace setter call acts absent, extractor wins",
			ctx:        WithTraceID(context.Background(), ""),
			extractor:  func(context.Context) string { return "span-1" },
			wantKeys:   map[string]any{traceIDAttr: "span-1"},
			absentKeys: []string{requestIDAttr, subjectIDAttr},
		},
		{
			name:       "empty request id setter call acts absent",
			ctx:        WithRequestID(context.Background(), ""),
			absentKeys: []string{requestIDAttr, subjectIDAttr, traceIDAttr},
		},
		{
			name:       "trace only via extractor",
			ctx:        context.Background(),
			extractor:  func(context.Context) string { return "span-1" },
			wantKeys:   map[string]any{traceIDAttr: "span-1"},
			absentKeys: []string{requestIDAttr, subjectIDAttr},
		},
		{
			name:       "empty extractor result counts as absent",
			ctx:        context.Background(),
			extractor:  func(context.Context) string { return "" },
			absentKeys: []string{requestIDAttr, subjectIDAttr, traceIDAttr},
		},
		{
			name:       "over-long extractor result dropped",
			ctx:        context.Background(),
			extractor:  func(context.Context) string { return strings.Repeat("x", maxCorrelationIDLen+1) },
			absentKeys: []string{requestIDAttr, subjectIDAttr, traceIDAttr},
		},
		{
			name:       "control-char extractor result dropped",
			ctx:        context.Background(),
			extractor:  func(context.Context) string { return "\x1b[31mred\x1b[0m" },
			absentKeys: []string{requestIDAttr, subjectIDAttr, traceIDAttr},
		},
		{
			name:       "zero subject id is present",
			ctx:        WithSubjectID(context.Background(), 0),
			wantKeys:   map[string]any{subjectIDAttr: float64(0)},
			absentKeys: []string{requestIDAttr, traceIDAttr},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			buf, logger := captureJSON(ContextHandlerOptions{TraceIDExtractor: tt.extractor})
			logger.InfoContext(tt.ctx, "line")

			ms := parseLines(t, buf.Bytes())
			if len(ms) != 1 {
				t.Fatalf("got %d lines, want 1: %s", len(ms), buf.String())
			}
			for key, want := range tt.wantKeys {
				if got := ms[0][key]; got != want {
					t.Errorf("%s = %v, want %v", key, got, want)
				}
			}
			for _, key := range tt.absentKeys {
				if _, ok := ms[0][key]; ok {
					t.Errorf("absent field %q emitted: %s", key, buf.String())
				}
			}
		})
	}
}

// TestContextHandlerTraceKeyWinsOverExtractor asserts a context trace id
// always beats the extractor fallback.
func TestContextHandlerTraceKeyWinsOverExtractor(t *testing.T) {
	buf, logger := captureJSON(ContextHandlerOptions{
		TraceIDExtractor: func(context.Context) string { return "from-span" },
	})
	logger.InfoContext(WithTraceID(context.Background(), "from-key"), "line")

	ms := parseLines(t, buf.Bytes())
	if got := ms[0][traceIDAttr]; got != "from-key" {
		t.Errorf("trace_id = %v, want %q (key first)", got, "from-key")
	}
}

// TestContextHandlerDuplicateKeyGuard asserts a record that already carries
// an owned key keeps its own value and is not duplicated (go1.26 built-ins
// no longer deduplicate keys), while the other fields still inject.
func TestContextHandlerDuplicateKeyGuard(t *testing.T) {
	buf, logger := captureJSON(ContextHandlerOptions{})
	logger.InfoContext(correlationCtx(), "line", slog.String(requestIDAttr, "preset"))

	out := buf.String()
	if got := strings.Count(out, `"`+requestIDAttr+`"`); got != 1 {
		t.Errorf("%q appears %d times, want exactly 1: %s", requestIDAttr, got, out)
	}
	if !strings.Contains(out, `"request_id":"preset"`) {
		t.Errorf("pre-set request_id not preserved: %s", out)
	}
	if strings.Contains(out, "req-123") {
		t.Errorf("ctx request_id injected despite pre-set record attr: %s", out)
	}

	ms := parseLines(t, buf.Bytes())
	if got := ms[0][subjectIDAttr]; got != float64(42) {
		t.Errorf("subject_id = %v, want 42", got)
	}
	if got := ms[0][traceIDAttr]; got != "trace-abc" {
		t.Errorf("trace_id = %v, want %q", got, "trace-abc")
	}
}

// TestContextHandlerWithAttrsFiltered asserts owned keys re-added via
// logger.With are dropped while ctx values and other attrs still emit.
func TestContextHandlerWithAttrsFiltered(t *testing.T) {
	t.Run("owned keys dropped on With, ctx values inject", func(t *testing.T) {
		buf, logger := captureJSON(ContextHandlerOptions{ServiceName: "svc"})
		logger.With(
			slog.String(requestIDAttr, "override"),
			slog.Int64(subjectIDAttr, 999),
			slog.String(serviceAttr, "override-svc"),
			slog.String("static", "attr"),
		).InfoContext(correlationCtx(), "line")

		out := buf.String()
		ms := parseLines(t, buf.Bytes())
		if len(ms) != 1 {
			t.Fatalf("got %d lines, want 1: %s", len(ms), out)
		}
		for _, key := range []string{requestIDAttr, subjectIDAttr, serviceAttr} {
			if got := strings.Count(out, `"`+key+`"`); got != 1 {
				t.Errorf("%q appears %d times, want exactly 1 (no duplicate keys): %s", key, got, out)
			}
		}
		if got := ms[0][requestIDAttr]; got != "req-123" {
			t.Errorf("request_id = %v, want ctx value %q", got, "req-123")
		}
		if got := ms[0][subjectIDAttr]; got != float64(42) {
			t.Errorf("subject_id = %v, want ctx value 42", got)
		}
		if got := ms[0][serviceAttr]; got != "svc" {
			t.Errorf("service = %v, want configured %q", got, "svc")
		}
		if got := ms[0]["static"]; got != "attr" {
			t.Errorf("non-owned With attr lost: %v", got)
		}
	})

	t.Run("service not owned while ServiceName unset", func(t *testing.T) {
		buf, logger := captureJSON(ContextHandlerOptions{})
		logger.With(slog.String(serviceAttr, "custom")).InfoContext(context.Background(), "line")

		ms := parseLines(t, buf.Bytes())
		if got := ms[0][serviceAttr]; got != "custom" {
			t.Errorf("service = %v, want %q (must pass through when not owned)", got, "custom")
		}
	})
}

// TestContextHandlerChildLoggers asserts With/WithGroup children keep
// injecting. With go1.26 handlers, record attrs (including injected ones)
// nest under open groups, so the grouped line is asserted
// location-agnostically.
func TestContextHandlerChildLoggers(t *testing.T) {
	buf, logger := captureJSON(ContextHandlerOptions{})
	ctx := correlationCtx()

	logger.With(slog.String("static", "attr")).InfoContext(ctx, "with child")
	logger.WithGroup("g").With(slog.String("k", "v")).InfoContext(ctx, "grouped child")

	ms := parseLines(t, buf.Bytes())
	if len(ms) != 2 {
		t.Fatalf("got %d lines, want 2: %s", len(ms), buf.String())
	}

	// With child: handler attrs and injected fields all at top level.
	m0 := ms[0]
	if got := m0["static"]; got != "attr" {
		t.Errorf("With attr lost: %v", got)
	}
	for key, want := range map[string]any{
		requestIDAttr: "req-123", subjectIDAttr: float64(42), traceIDAttr: "trace-abc",
	} {
		if got := m0[key]; got != want {
			t.Errorf("With child %s = %v, want %v", key, got, want)
		}
	}

	// WithGroup child: the group is intact, and the injected fields are
	// present in the emitted line (nested under g by the stdlib handler).
	g, ok := ms[1]["g"].(map[string]any)
	if !ok {
		t.Fatalf("group g missing or not a map: %s", buf.String())
	}
	if got := g["k"]; got != "v" {
		t.Errorf("group attr k = %v, want %q", got, "v")
	}
	for key, want := range map[string]any{
		requestIDAttr: "req-123", subjectIDAttr: float64(42), traceIDAttr: "trace-abc",
	} {
		if got := g[key]; got != want {
			t.Errorf("WithGroup child %s = %v, want %v", key, got, want)
		}
	}
}

// TestContextHandlerService asserts the service attr is emitted exactly when
// ServiceName is configured.
func TestContextHandlerService(t *testing.T) {
	buf, logger := captureJSON(ContextHandlerOptions{ServiceName: "league-tokens-backend"})
	logger.InfoContext(context.Background(), "line")

	ms := parseLines(t, buf.Bytes())
	if got := ms[0][serviceAttr]; got != "league-tokens-backend" {
		t.Errorf("service = %v, want %q", got, "league-tokens-backend")
	}

	buf2, logger2 := captureJSON(ContextHandlerOptions{})
	logger2.InfoContext(context.Background(), "line")
	ms2 := parseLines(t, buf2.Bytes())
	if _, ok := ms2[0][serviceAttr]; ok {
		t.Errorf("service emitted with empty ServiceName: %s", buf2.String())
	}
}

// TestContextHandlerNilCtx asserts Handle(nil, r) never panics: nil ctx is
// treated as background (no keys, extractor runs, service still injected).
func TestContextHandlerNilCtx(t *testing.T) {
	var buf bytes.Buffer
	h := NewContextHandler(NewHandler(slog.LevelDebug, FormatJSON, &buf), ContextHandlerOptions{
		ServiceName:      "svc",
		TraceIDExtractor: func(context.Context) string { return "no-panic" },
	})
	r := slog.NewRecord(time.Time{}, slog.LevelInfo, "nil ctx line", 0)

	// Pass nil through a variable: the runtime value is nil (exercising the
	// nil-ctx guard) without tripping staticcheck SA1012 on a literal nil.
	var nilCtx context.Context
	if !h.Enabled(nilCtx, slog.LevelInfo) {
		t.Fatal("Enabled(nil, INFO) = false, want true")
	}
	if err := h.Handle(nilCtx, r); err != nil {
		t.Fatalf("Handle(nil, r) error = %v", err)
	}

	ms := parseLines(t, buf.Bytes())
	if len(ms) != 1 {
		t.Fatalf("got %d lines, want 1: %s", len(ms), buf.String())
	}
	if got := ms[0]["msg"]; got != "nil ctx line" {
		t.Errorf("msg = %v, want %q", got, "nil ctx line")
	}
	if got := ms[0][serviceAttr]; got != "svc" {
		t.Errorf("service = %v, want %q", got, "svc")
	}
	if got := ms[0][traceIDAttr]; got != "no-panic" {
		t.Errorf("trace_id = %v, want %q", got, "no-panic")
	}
}

// TestNewContextHandlerNilHandler asserts a nil wrapped handler fails fast
// at construction instead of nil-dereferencing at the first log call site.
func TestNewContextHandlerNilHandler(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Fatal("NewContextHandler(nil, ...) did not panic")
		}
	}()
	NewContextHandler(nil, ContextHandlerOptions{})
}

// TestNewContextHandlerInvalidServiceName asserts invalid direct options
// fail at construction, matching TelemetryConfig.Validate's boot-time guard.
func TestNewContextHandlerInvalidServiceName(t *testing.T) {
	tests := []struct {
		name  string
		value string
	}{
		{name: "overlong", value: strings.Repeat("x", maxCorrelationIDLen+1)},
		{name: "control_chars", value: "svc\x1b[31mred\x1b[0m"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			defer func() {
				if recover() == nil {
					t.Fatalf("NewContextHandler accepted invalid SERVICE_NAME %q", tt.value)
				}
			}()
			NewContextHandler(NewHandler(slog.LevelDebug, FormatJSON, io.Discard), ContextHandlerOptions{ServiceName: tt.value})
		})
	}
}

// typedNilHandler implements slog.Handler through a pointer so the test can
// exercise an interface containing a typed nil pointer.
type typedNilHandler struct{}

func (*typedNilHandler) Enabled(context.Context, slog.Level) bool  { return true }
func (*typedNilHandler) Handle(context.Context, slog.Record) error { return nil }
func (h *typedNilHandler) WithAttrs([]slog.Attr) slog.Handler      { return h }
func (h *typedNilHandler) WithGroup(string) slog.Handler           { return h }

func TestNewContextHandlerTypedNilHandler(t *testing.T) {
	var h *typedNilHandler
	defer func() {
		if recover() == nil {
			t.Fatal("NewContextHandler accepted a typed-nil handler")
		}
	}()
	NewContextHandler(h, ContextHandlerOptions{})
}

// BenchmarkContextHandlerHandle quantifies the per-record cost of the
// decorator relative to the raw handler (finding: clone + AddAttrs when
// correlation fields are present).
func BenchmarkContextHandlerHandle(b *testing.B) {
	raw := NewHandler(slog.LevelDebug, FormatJSON, io.Discard)
	decorated := NewContextHandler(raw, ContextHandlerOptions{})
	ctxFull := correlationCtx()
	r := slog.NewRecord(time.Time{}, slog.LevelInfo, "bench line", 0)
	r.AddAttrs(slog.String("static", "attr"))

	b.Run("raw/empty-ctx", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			if err := raw.Handle(context.Background(), r); err != nil {
				b.Fatal(err)
			}
		}
	})
	b.Run("decorated/empty-ctx", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			if err := decorated.Handle(context.Background(), r); err != nil {
				b.Fatal(err)
			}
		}
	})
	b.Run("decorated/full-ctx", func(b *testing.B) {
		b.ReportAllocs()
		for i := 0; i < b.N; i++ {
			if err := decorated.Handle(ctxFull, r); err != nil {
				b.Fatal(err)
			}
		}
	})
}

// TestContextHandlerSlogtest runs the stdlib handler-contract suite against
// the decorator (all four methods must be forwarded correctly).
func TestContextHandlerSlogtest(t *testing.T) {
	var buf bytes.Buffer
	h := NewContextHandler(NewHandler(slog.LevelDebug, FormatJSON, &buf), ContextHandlerOptions{})

	err := slogtest.TestHandler(h, func() []map[string]any {
		return parseLines(t, buf.Bytes())
	})
	if err != nil {
		t.Fatal(err)
	}
}
