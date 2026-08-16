// Package log is the app's shared slog layer (spec §7.3; ADR-0006, ADR-0011):
// the Format-aware handler factory (text dev, JSON prod) and the context
// keys/accessors carrying the ADR-0011 correlation fields into every log
// line. Stdlib-only, freely importable (ADR-0008).
//
// # Field ownership
//
// The six names code, op, service, subject_id, trace_id, request_id are
// owned by this package — call sites must not re-add them as attrs.
// request_id, subject_id, and trace_id are injected from ctx by
// ContextHandler; service is injected by ContextHandler when ServiceName is
// set (SERVICE_NAME); code and op are call-site attrs via Code()/Op()
// (per-line semantics — not auto-injectable), drawn from the ADR-0011 table
// until the error-model issue ships apperr/codes.go. The decorator drops
// owned keys re-added via logger.With (ContextHandler.WithAttrs) — even
// when the ctx field is absent, so logger.With must not be used to set
// correlation values. The slog built-ins time, level, msg, source are
// reserved — go1.26 no longer filters collisions, so a duplicate key would
// be emitted.
//
// # op convention
//
// op is a dotted context.Operation string mirroring the ADR-0011 code
// prefixes (game.ResolveMatch, …) so log attrs align with ops_total{op}.
//
// # No PII
//
// Tokens must never be logged; secret-bearing values must be redacted
// (slog.LogValuer or scrubbing) before reaching a record.
//
// # Seam contract (populated by #8/#11/#42)
//
// #8's middlewares call WithRequestID/WithTraceID; #11's auth middleware
// calls WithSubjectID; #42 wires the span-context fallback into the
// decorator. Values absent from ctx are not emitted — the decorator is
// nil-safe. Correlation ids are bounded (≤128 bytes, no control chars) at
// the setters and the injection path, so a hostile value can neither
// amplify logs nor inject terminal escapes into dev text logs. Empty ids
// are never stored (empty-string = absent); an absent trace key lets the
// TraceIDExtractor fallback run.
package log

import "log/slog"

// Op returns the op attr for a dotted context.Operation string, e.g.
// Op("game.ResolveMatch"). The value must mirror the ADR-0011 code prefixes
// so log attrs stay aligned with ops_total{op}.
func Op(op string) slog.Attr {
	return slog.String("op", op)
}

// Code returns the code attr for a stable dotted ADR-0011 code string,
// e.g. Code("game.phase_closed"). Like op, it is a per-line call-site attr
// (the decorator cannot inject it); values must be canonical in the
// ADR-0011 table (apperr/codes.go lands with the error-model issue).
func Code(code string) slog.Attr {
	return slog.String("code", code)
}
