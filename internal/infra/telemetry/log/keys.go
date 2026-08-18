package log

import (
	"context"
	"unicode"
)

// maxCorrelationIDLen bounds request/trace ids at 128 bytes.
const maxCorrelationIDLen = 128

// ValidLogString reports whether s is safe to emit as a log attr value:
// non-empty (empty-string = absent), ≤ maxCorrelationIDLen bytes, no control
// chars (terminal-escape safety for dev text logs). Shared by the
// correlation-id setters, the decorator's injection path, and
// TelemetryConfig.Validate (SERVICE_NAME), so a hostile value is never
// stored, emitted, nor accepted at boot. Named for the general case —
// service names carry the same bounds as correlation ids (ADR-0011).
func ValidLogString(s string) bool {
	if s == "" || len(s) > maxCorrelationIDLen {
		return false
	}
	for _, r := range s {
		if unicode.IsControl(r) {
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

// normalizeContext substitutes context.Background() for a nil ctx so the
// setters and getters are as nil-safe as the decorator (ContextHandler
// normalizes the same way; a nil ctx never panics).
func normalizeContext(ctx context.Context) context.Context {
	if ctx == nil {
		return context.Background()
	}
	return ctx
}

// WithRequestID stores the request id in ctx (ctx unchanged when id fails
// the correlation bounds). Called by #8's req_id middleware, which should
// prefer server-generated ids and validate client-supplied headers first.
// A nil ctx is treated as context.Background().
func WithRequestID(ctx context.Context, id string) context.Context {
	ctx = normalizeContext(ctx)
	if !ValidLogString(id) {
		return ctx
	}
	return context.WithValue(ctx, requestIDKey{}, id)
}

// RequestID returns the request id from ctx, if present. A nil ctx is
// treated as context.Background() and reports absent.
func RequestID(ctx context.Context) (string, bool) {
	id, ok := normalizeContext(ctx).Value(requestIDKey{}).(string)
	return id, ok
}

// WithSubjectID stores the subject id (int64 — bigint in the data model,
// ADR-0003/ADR-0007). Called by #11's auth middleware. A nil ctx is
// treated as context.Background().
func WithSubjectID(ctx context.Context, id int64) context.Context {
	return context.WithValue(normalizeContext(ctx), subjectIDKey{}, id)
}

// SubjectID returns the subject id from ctx, if present. A nil ctx is
// treated as context.Background() and reports absent.
func SubjectID(ctx context.Context) (int64, bool) {
	id, ok := normalizeContext(ctx).Value(subjectIDKey{}).(int64)
	return id, ok
}

// WithTraceID stores the trace id in ctx (ctx unchanged when id fails the
// correlation bounds). The ctx value wins over the extractor; #8's
// middleware populates it and #42 adds the span-context fallback. A nil ctx
// is treated as context.Background().
func WithTraceID(ctx context.Context, id string) context.Context {
	ctx = normalizeContext(ctx)
	if !ValidLogString(id) {
		return ctx
	}
	return context.WithValue(ctx, traceIDKey{}, id)
}

// TraceID returns the trace id from ctx, if present. A nil ctx is treated
// as context.Background() and reports absent.
func TraceID(ctx context.Context) (string, bool) {
	id, ok := normalizeContext(ctx).Value(traceIDKey{}).(string)
	return id, ok
}
