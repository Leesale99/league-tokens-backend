// Package log is the app's shared slog layer (spec §7.3; ADR-0006, ADR-0011).
// It owns the Format-aware handler factory (text in dev, JSON in production)
// and the context keys/accessors that carry the ADR-0011 correlation fields
// from the request context into every log line. The package is stdlib-only
// (log/slog) and freely importable by every context (ADR-0008).
//
// # Field ownership
//
// The five names code, op, subject_id, trace_id, request_id are owned by
// this package: call sites must not re-add them as attrs. request-scoped
// lines get request_id, subject_id, and trace_id from ctx — injected by the
// context-decorating handler (task 03) at emit time, so handlers do not
// repeat them. code and op are call-site attrs: op via Op(), code as a plain
// string from the ADR-0011 canonical table until the error-model issue ships
// apperr/codes.go. The four slog built-ins time, level, msg, source are
// conventionally reserved: never use them as user attr names — go1.26 no
// longer filters collisions, so a duplicate key would be emitted.
//
// # The op convention
//
// op is a dotted context.Operation string mirroring the
// ADR-0011 code prefixes (game.ResolveMatch, config.Load, ...) so log attrs
// stay aligned with the spec's ops_total{op} metric label.
//
// # No PII
//
// Tokens must never be logged. Secret-bearing values must be
// redacted (slog.LogValuer or scrubbing) before they reach a record.
//
// # Seam contract (populated by later issues, no rework needed)
//
// #8's edge middlewares call WithRequestID (and WithTraceID); #11's auth
// middleware calls WithSubjectID(int64); #42 wires the trace_id span
// fallback into the context decorator. Values absent from ctx are simply
// not emitted — the decorator is nil-safe.
//
// Empty-string = absent: an empty request/trace id is never stored by the
// setters and never emitted; for trace_id, an absent or empty key value lets
// the TraceIDExtractor fallback run (B-2). Correlation ids are bounded by
// validCorrelationID (≤128 bytes, no control characters) at both the setters
// and the decorator's injection path, so a hostile value can neither amplify
// logs nor inject terminal escapes into dev text logs. #8 should prefer
// server-generated ids; any value derived from client-supplied headers must
// be validated by #8's middleware before calling the setters.
package log

import "log/slog"

// Op returns the op attr for a dotted context.Operation string, e.g.
// Op("game.ResolveMatch"). The value must mirror the ADR-0011 code prefixes
// so log attrs stay aligned with ops_total{op}.
func Op(op string) slog.Attr {
	return slog.String("op", op)
}
