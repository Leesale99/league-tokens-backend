package log

import (
	"context"
	"log/slog"
)

// Attr names owned by the decorator — call sites must not re-add them
// (package doc: Field ownership).
const (
	requestIDAttr = "request_id"
	subjectIDAttr = "subject_id"
	traceIDAttr   = "trace_id"
	serviceAttr   = "service"
)

// ContextHandlerOptions configures the context-decorating handler.
type ContextHandlerOptions struct {
	// ServiceName, when non-empty, is injected as a "service" attr on every
	// record the handler emits.
	ServiceName string

	// TraceIDExtractor derives a trace id from ctx when no usable
	// WithTraceID value is present. Nil disables it; #42 wires
	// trace.SpanContextFromContext here.
	TraceIDExtractor func(context.Context) string
}

// ContextHandler decorates a slog.Handler so every record it emits carries
// the ADR-0011 correlation fields present in the record's context:
// request_id and subject_id (set by the #8/#11 middlewares), trace_id (ctx
// value first, then TraceIDExtractor), and "service" when ServiceName is
// set. Values absent from ctx are not emitted; keys the record already
// carries are not injected again (go1.26 built-in handlers no longer
// deduplicate keys, so a repeat would emit a duplicate) — WithAttrs drops
// owned keys re-added via logger.With, even when the ctx field is absent:
// logger.With must not be used to set correlation values (pass them as
// per-record attrs or via the ctx seam instead).
//
// Child loggers (With/WithGroup) keep injecting. With an open group the
// injected attrs nest under it like any record attr — do not use WithGroup
// if they must stay top-level. A nil ctx never panics. Injection clones
// the record (handler contract: never mutate in place); for typical records
// (≤5 attrs) the clone reuses the record's front-attr array, so the
// decorator adds no allocations — see BenchmarkContextHandlerHandle.
type ContextHandler struct {
	next slog.Handler
	opts ContextHandlerOptions
}

// isOwned reports whether key is owned by the decorator: injected (and
// dropped from logger.With) whenever the ctx provides it, or — for
// "service" — whenever ServiceName is set. Single source of the owned set,
// shared by Handle and WithAttrs so a new owned field needs exactly one
// edit.
func isOwned(key string, opts ContextHandlerOptions) bool {
	switch key {
	case requestIDAttr, subjectIDAttr, traceIDAttr:
		return true
	case serviceAttr:
		return opts.ServiceName != ""
	}
	return false
}

// NewContextHandler returns a handler that decorates h with context-value
// injection. h must be a freshly built handler (e.g. NewHandler) — never one
// captured from slog.Default(), which would deadlock a subsequent
// slog.SetDefault (golang/go#61892).
func NewContextHandler(h slog.Handler, opts ContextHandlerOptions) *ContextHandler {
	if h == nil {
		panic("telemetry/log: NewContextHandler requires a non-nil handler")
	}
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

	// Inject present values unless the record already carries the key —
	// go1.26 built-in handlers no longer deduplicate, so a repeat would
	// emit a duplicate key.
	var attrs [4]slog.Attr
	inject := attrs[:0]
	if id, ok := RequestID(ctx); ok && ValidCorrelationID(id) && !recordHasKey(r, requestIDAttr) {
		inject = append(inject, slog.String(requestIDAttr, id))
	}
	if id, ok := SubjectID(ctx); ok && !recordHasKey(r, subjectIDAttr) {
		inject = append(inject, slog.Int64(subjectIDAttr, id))
	}
	if id, ok := c.traceID(ctx); ok && !recordHasKey(r, traceIDAttr) {
		inject = append(inject, slog.String(traceIDAttr, id))
	}
	if c.opts.ServiceName != "" && ValidCorrelationID(c.opts.ServiceName) && !recordHasKey(r, serviceAttr) {
		inject = append(inject, slog.String(serviceAttr, c.opts.ServiceName))
	}

	if len(inject) == 0 {
		return c.next.Handle(ctx, r)
	}

	// Handler contract: never mutate the record in place — clone first.
	r2 := r.Clone()
	r2.AddAttrs(inject...)
	return c.next.Handle(ctx, r2)
}

// traceID returns the trace id to inject: the ctx value first, then the
// extractor output; both must pass the correlation bounds.
func (c *ContextHandler) traceID(ctx context.Context) (string, bool) {
	if id, ok := TraceID(ctx); ok && ValidCorrelationID(id) {
		return id, true
	}
	if c.opts.TraceIDExtractor == nil {
		return "", false
	}
	if id := c.opts.TraceIDExtractor(ctx); ValidCorrelationID(id) {
		return id, true
	}
	return "", false
}

// recordHasKey reports whether the record already carries key.
// Handler-level duplicates are prevented by WithAttrs instead.
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

// WithAttrs returns a child handler carrying attrs. Owned keys (isOwned)
// are dropped: the decorator injects them itself (or, for "service" when
// ServiceName is unset, they pass through), and go1.26 built-ins no longer
// deduplicate keys.
func (c *ContextHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	for _, a := range attrs {
		if !isOwned(a.Key, c.opts) {
			continue
		}
		kept := make([]slog.Attr, 0, len(attrs))
		for _, b := range attrs {
			if !isOwned(b.Key, c.opts) {
				kept = append(kept, b)
			}
		}
		return &ContextHandler{next: c.next.WithAttrs(kept), opts: c.opts}
	}
	return &ContextHandler{next: c.next.WithAttrs(attrs), opts: c.opts}
}

// WithGroup appends the group to the wrapped handler; see the type doc for
// how an open group nests the injected attrs.
func (c *ContextHandler) WithGroup(name string) slog.Handler {
	return &ContextHandler{next: c.next.WithGroup(name), opts: c.opts}
}
