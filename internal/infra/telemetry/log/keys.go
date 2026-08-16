package log

import "context"

// maxCorrelationIDLen bounds request/trace ids at 128 bytes.
const maxCorrelationIDLen = 128

// validCorrelationID reports whether id may carry correlation: non-empty
// (empty-string = absent), ≤ maxCorrelationIDLen bytes, no control chars
// (terminal-escape safety for dev text logs). Shared by setters and the
// injection path, so a hostile value is never stored nor emitted.
func validCorrelationID(id string) bool {
	if id == "" || len(id) > maxCorrelationIDLen {
		return false
	}
	for _, r := range id {
		if r < 0x20 || r == 0x7f {
			return false
		}
	}
	return true
}

// Distinct unexported struct types per key so values can never collide with
// each other or with other packages' context values.
type requestIDKey struct{}
type subjectIDKey struct{}
type traceIDKey struct{}

// WithRequestID stores the request id in ctx (ctx unchanged when id fails
// the correlation bounds). Called by #8's req_id middleware, which should
// prefer server-generated ids and validate client-supplied headers first.
func WithRequestID(ctx context.Context, id string) context.Context {
	if !validCorrelationID(id) {
		return ctx
	}
	return context.WithValue(ctx, requestIDKey{}, id)
}

// RequestID returns the request id from ctx, if present.
func RequestID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(requestIDKey{}).(string)
	return id, ok
}

// WithSubjectID stores the subject id (int64 — bigint in the data model,
// ADR-0003/ADR-0007). Called by #11's auth middleware.
func WithSubjectID(ctx context.Context, id int64) context.Context {
	return context.WithValue(ctx, subjectIDKey{}, id)
}

// SubjectID returns the subject id from ctx, if present.
func SubjectID(ctx context.Context) (int64, bool) {
	id, ok := ctx.Value(subjectIDKey{}).(int64)
	return id, ok
}

// WithTraceID stores the trace id in ctx (ctx unchanged when id fails the
// correlation bounds). The ctx value wins over the extractor; #8's
// middleware populates it and #42 adds the span-context fallback.
func WithTraceID(ctx context.Context, id string) context.Context {
	if !validCorrelationID(id) {
		return ctx
	}
	return context.WithValue(ctx, traceIDKey{}, id)
}

// TraceID returns the trace id from ctx, if present.
func TraceID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(traceIDKey{}).(string)
	return id, ok
}
