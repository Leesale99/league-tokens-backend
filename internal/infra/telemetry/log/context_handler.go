package log

import (
	"context"
	"log/slog"
)

// Emitted attr names owned by the context decorator: the three ADR-0011
// correlation fields plus the per-record service name (F-4). The package
// doc's field ownership rule covers them — call sites must not re-add these
// as attrs.
const (
	requestIDAttr = "request_id"
	subjectIDAttr = "subject_id"
	traceIDAttr   = "trace_id"
	serviceAttr   = "service"
)

// ContextHandlerOptions configures the context-decorating handler.
type ContextHandlerOptions struct {
	// ServiceName, when non-empty, is injected as a "service" attr on every
	// record the handler emits (F-4: per-record service name). Task 04
	// passes TelemetryConfig.ServiceName here.
	ServiceName string

	// TraceIDExtractor derives a trace id from ctx when the context carries
	// no WithTraceID value — decision B-2: key first, extractor second;
	// absent both → the field is not emitted. #42 wires
	// trace.SpanContextFromContext(ctx) here without rework. Nil disables
	// the fallback.
	TraceIDExtractor func(context.Context) string
}

// ContextHandler decorates h so every record it emits carries the ADR-0011
// correlation fields present in the record's context: request_id and
// subject_id (set by #8/#11 middlewares via WithRequestID/WithSubjectID)
// and trace_id (key first, then TraceIDExtractor). When ServiceName is
// set, a "service" attr is added too. Fields absent from ctx are not
// emitted; fields the record already carries are not injected again —
// go1.26 built-in handlers no longer deduplicate keys, so a repeat would
// emit duplicate JSON keys.
//
// It implements slog.Handler by forwarding all four methods. Enabled and
// Handle delegate to the wrapped handler (which does the formatting);
// WithAttrs and WithGroup wrap the wrapped handler's result and preserve
// the options, so child loggers keep injecting. Injection happens on a
// clone of the record in Handle, so the injected fields become ordinary
// record attrs emitted by the wrapped handler after its built-ins.
//
// Group caveat (verified against go1.26 stdlib): the built-in JSON/Text
// handlers emit record attrs inside the groups opened by WithGroup
// (handler.go appendNonBuiltIns wraps them in openGroups), so a WithGroup
// child logger nests the injected fields under the group. That is how
// every record attr behaves with an open group — blocky's contextHandler
// documents the same — so injection still happens; if the fields must
// stay top-level, do not call WithGroup on a context-aware logger.
//
// The decorator never panics on a nil ctx (treated as context.Background(),
// as the stdlib Logger does). The constructor takes a freshly built handler
// (e.g. NewHandler) — never one captured from slog.Default(), which would
// deadlock a subsequent SetDefault (golang/go#61892).
type ContextHandler struct {
	next slog.Handler
	opts ContextHandlerOptions
}

// NewContextHandler returns a handler that decorates h with context-value
// injection.
func NewContextHandler(h slog.Handler, opts ContextHandlerOptions) *ContextHandler {
	return &ContextHandler{next: h, opts: opts}
}

// Enabled delegates the level decision to the wrapped handler.
func (c *ContextHandler) Enabled(ctx context.Context, level slog.Level) bool {
	if ctx == nil {
		ctx = context.Background()
	}
	return c.next.Enabled(ctx, level)
}

// Handle injects the correlation fields present in ctx into the record and
// delegates to the wrapped handler.
func (c *ContextHandler) Handle(ctx context.Context, r slog.Record) error {
	if ctx == nil {
		ctx = context.Background()
	}

	var attrs []slog.Attr
	appendIfAbsent := func(key string, a slog.Attr) {
		if recordHasKey(r, key) {
			return
		}
		attrs = append(attrs, a)
	}

	if id, ok := RequestID(ctx); ok {
		appendIfAbsent(requestIDAttr, slog.String(requestIDAttr, id))
	}
	if id, ok := SubjectID(ctx); ok {
		appendIfAbsent(subjectIDAttr, slog.Int64(subjectIDAttr, id))
	}
	if id, ok := TraceID(ctx); ok {
		appendIfAbsent(traceIDAttr, slog.String(traceIDAttr, id))
	} else if ext := c.opts.TraceIDExtractor; ext != nil {
		// B-2: key first; the extractor (OTel span context in #42) only
		// fills in when the key is absent, and an empty result counts as
		// absent.
		if id := ext(ctx); id != "" {
			appendIfAbsent(traceIDAttr, slog.String(traceIDAttr, id))
		}
	}
	if c.opts.ServiceName != "" {
		appendIfAbsent(serviceAttr, slog.String(serviceAttr, c.opts.ServiceName))
	}

	if len(attrs) == 0 {
		return c.next.Handle(ctx, r)
	}

	// Handler contract: never mutate the record in place — clone before
	// adding.
	r2 := r.Clone()
	r2.AddAttrs(attrs...)
	return c.next.Handle(ctx, r2)
}

// WithAttrs returns a new ContextHandler whose wrapped handler carries
// attrs, preserving the options so child loggers keep injecting.
func (c *ContextHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &ContextHandler{next: c.next.WithAttrs(attrs), opts: c.opts}
}

// WithGroup returns a new ContextHandler with the group appended to the
// wrapped handler's groups, preserving the options so child loggers keep
// injecting. See the type doc for how an open group places the injected
// record attrs.
func (c *ContextHandler) WithGroup(name string) slog.Handler {
	return &ContextHandler{next: c.next.WithGroup(name), opts: c.opts}
}

// recordHasKey reports whether the record's attrs already carry key. The
// guard scans r.Attrs because that is the only place a call site can put an
// owned key on a record; handler-level attrs (logger.With) are ownership
// violations covered by the package doc, not detectable generically here.
func recordHasKey(r slog.Record, key string) bool {
	has := false
	r.Attrs(func(a slog.Attr) bool {
		if a.Key == key {
			has = true
			return false
		}
		return true
	})
	return has
}
