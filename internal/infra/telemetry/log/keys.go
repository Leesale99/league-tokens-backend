package log

import "context"

// maxCorrelationIDLen bounds request/trace ids at 128 bytes (security I-1:
// unbounded ids would let a client-supplied value amplify every request-scoped
// log line and drive the observability pipeline).
const maxCorrelationIDLen = 128

// validCorrelationID reports whether id may carry request_id/trace_id
// correlation: non-empty (empty-string = absent), at most
// maxCorrelationIDLen bytes, and free of control characters (rune < 0x20 or
// DEL 0x7f) — the last keeps dev text logs free of terminal-escape
// injection. Shared by the two string setters and the context decorator's
// injection path, so a hostile value cannot be stored nor emitted.
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

// WithRequestID returns a copy of ctx carrying the request id, or ctx
// unchanged when id fails the correlation bounds (empty-string = absent).
// Called by #8's req_id edge middleware — prefer server-generated ids there
// and validate client-supplied headers before calling the setter (seam
// contract); the context decorator injects the value into request-scoped log
// records.
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

// WithTraceID returns a copy of ctx carrying the trace id, or ctx unchanged
// when id fails the correlation bounds (empty-string = absent). Key-first per
// decision B-2: #8's middleware can populate it today; #42 attaches the
// OTel span-context fallback to the context decorator without rework.
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
