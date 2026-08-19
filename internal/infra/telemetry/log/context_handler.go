package log

import (
	"context"
	"log/slog"
	"reflect"
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
	// ServiceName, when non-empty and valid according to ValidLogString,
	// is injected as a "service" attr on every record the handler emits.
	// NewContextHandler rejects invalid values.
	ServiceName string

	// TraceIDExtractor derives a trace id from ctx when no usable
	// WithTraceID value is present. Nil disables it; #42 should adapt
	// trace.SpanContextFromContext to return its valid TraceID().String().
	TraceIDExtractor func(context.Context) string
}

// ContextHandler decorates a slog.Handler so every record it emits carries
// the ADR-0011 correlation fields present in the record's context:
// request_id and subject_id (set by the #8/#11 middlewares), trace_id (ctx
// value first, then TraceIDExtractor), and "service" when ServiceName is
// set. Values absent from ctx are not emitted; keys the record already
// carries are not injected again — built-in handlers emit duplicate keys
// verbatim, so a repeat would emit a duplicate. Owned keys passed
// through logger.With are intentionally discarded, even when the ctx field
// is absent; use WithRequestID, WithSubjectID, or WithTraceID on the context
// instead. This keeps correlation fields request-scoped and prevents a
// reusable child logger from carrying stale IDs into another request.
//
// Child loggers (With/WithGroup) keep injecting. With an open group the
// injected attrs nest under it like any record attr — do not use WithGroup
// if they must stay top-level. A nil ctx never panics. Injection clones
// the record (handler contract: never mutate in place); the decorator adds
// no allocations while the record's existing attrs plus injected attrs fit
// slog.Record's inline storage — see BenchmarkContextHandlerHandle.
type ContextHandler struct {
	next slog.Handler
	opts ContextHandlerOptions
	// serviceOwned caches whether ServiceName is set and valid, computed
	// once at construction so Handle/WithAttrs do not re-scan it per record.
	serviceOwned bool
}

// isOwned reports whether key is owned by the decorator: injected (and
// dropped from logger.With) whenever the ctx provides it, or — for
// "service" — whenever ServiceName is set and valid. The service outcome is
// precomputed once at construction (serviceOwned). Handle and WithAttrs
// both use this predicate so their ownership policy stays consistent.
func isOwned(key string, serviceOwned bool) bool {
	switch key {
	case requestIDAttr, subjectIDAttr, traceIDAttr:
		return true
	case serviceAttr:
		return serviceOwned
	}
	return false
}

// NewContextHandler returns a handler that decorates h with context-value
// injection. h must be a freshly built handler (e.g. NewHandler) — never one
// captured from slog.Default(), which would deadlock a subsequent
// slog.SetDefault (golang/go#61892). A nil or typed-nil handler, or an
// invalid non-empty ServiceName, fails fast at construction.
func NewContextHandler(h slog.Handler, opts ContextHandlerOptions) *ContextHandler {
	if isNilHandler(h) {
		panic("telemetry/log: NewContextHandler requires a non-nil handler")
	}
	if opts.ServiceName != "" && !ValidLogString(opts.ServiceName) {
		panic("telemetry/log: ContextHandlerOptions.ServiceName must be at most 128 bytes and contain no control characters when non-empty")
	}
	return &ContextHandler{
		next:         h,
		opts:         opts,
		serviceOwned: opts.ServiceName != "",
	}
}

// isNilHandler detects both a nil interface and an interface containing a
// typed-nil value. The latter otherwise passes a direct h == nil check and
// panics only when the first handler method is called.
func isNilHandler(h slog.Handler) bool {
	if h == nil {
		return true
	}
	v := reflect.ValueOf(h)
	switch v.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Pointer, reflect.Slice:
		return v.IsNil()
	default:
		return false
	}
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
	// built-in handlers emit duplicate keys verbatim, so a repeat would
	// emit a duplicate.
	var attrs [4]slog.Attr
	inject := attrs[:0]
	if isOwned(requestIDAttr, c.serviceOwned) {
		if id, ok := RequestID(ctx); ok && ValidLogString(id) && !recordHasKey(r, requestIDAttr) {
			inject = append(inject, slog.String(requestIDAttr, id))
		}
	}
	if isOwned(subjectIDAttr, c.serviceOwned) {
		if id, ok := SubjectID(ctx); ok && !recordHasKey(r, subjectIDAttr) {
			inject = append(inject, slog.Int64(subjectIDAttr, id))
		}
	}
	if isOwned(traceIDAttr, c.serviceOwned) {
		if id, ok := c.traceID(ctx); ok && !recordHasKey(r, traceIDAttr) {
			inject = append(inject, slog.String(traceIDAttr, id))
		}
	}
	if isOwned(serviceAttr, c.serviceOwned) && !recordHasKey(r, serviceAttr) {
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
	if id, ok := TraceID(ctx); ok && ValidLogString(id) {
		return id, true
	}
	if c.opts.TraceIDExtractor == nil {
		return "", false
	}
	if id := c.opts.TraceIDExtractor(ctx); ValidLogString(id) {
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
// are intentionally dropped, including when the ctx field is absent; use
// the context setters for correlation values. The "service" attr passes
// through when ServiceName is unset. Filtering also prevents built-in
// handlers from emitting duplicate owned keys. When no owned key is present
// the attrs are forwarded untouched (no filtering allocation).
func (c *ContextHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	needsFilter := false
	for _, attr := range attrs {
		if isOwned(attr.Key, c.serviceOwned) {
			needsFilter = true
			break
		}
	}
	if !needsFilter {
		return &ContextHandler{next: c.next.WithAttrs(attrs), opts: c.opts, serviceOwned: c.serviceOwned}
	}
	kept := make([]slog.Attr, 0, len(attrs))
	for _, attr := range attrs {
		if !isOwned(attr.Key, c.serviceOwned) {
			kept = append(kept, attr)
		}
	}
	return &ContextHandler{next: c.next.WithAttrs(kept), opts: c.opts, serviceOwned: c.serviceOwned}
}

// WithGroup appends the group to the wrapped handler; see the type doc for
// how an open group nests the injected attrs.
func (c *ContextHandler) WithGroup(name string) slog.Handler {
	return &ContextHandler{next: c.next.WithGroup(name), opts: c.opts, serviceOwned: c.serviceOwned}
}
