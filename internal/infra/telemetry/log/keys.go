package log

import "context"

// Distinct unexported struct types per key so values can never collide with
// each other or with other packages' context values.
type requestIDKey struct{}
type subjectIDKey struct{}
type traceIDKey struct{}

// WithRequestID returns a copy of ctx carrying the request id. Called by
// #8's req_id edge middleware; the context decorator injects the value into
// request-scoped log records.
func WithRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, requestIDKey{}, id)
}

// RequestID returns the request id from ctx, if present.
func RequestID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(requestIDKey{}).(string)
	return id, ok
}

// WithSubjectID returns a copy of ctx carrying the subject id (int64 — the
// data model stores subject_id as bigint, ADR-0003/ADR-0007). Called by
// #11's auth middleware.
func WithSubjectID(ctx context.Context, id int64) context.Context {
	return context.WithValue(ctx, subjectIDKey{}, id)
}

// SubjectID returns the subject id from ctx, if present.
func SubjectID(ctx context.Context) (int64, bool) {
	id, ok := ctx.Value(subjectIDKey{}).(int64)
	return id, ok
}

// WithTraceID returns a copy of ctx carrying the trace id. Key-first per
// decision B-2: #8's middleware can populate it today; #42 attaches the
// OTel span-context fallback to the context decorator without rework.
func WithTraceID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, traceIDKey{}, id)
}

// TraceID returns the trace id from ctx, if present.
func TraceID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(traceIDKey{}).(string)
	return id, ok
}
