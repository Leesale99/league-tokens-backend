package log

import (
	"fmt"
	"io"
	"log/slog"
	"strings"
)

// Format selects the slog output format (ADR-0006: text in dev, JSON in
// production).
type Format int

const (
	FormatText Format = iota
	FormatJSON
)

// ParseFormat maps a LOG_FORMAT-style string to a Format ("text"/"json",
// case-insensitive). It is the single source of the whitelist:
// TelemetryConfig.Validate() delegates to it (ADR-0012).
func ParseFormat(s string) (Format, error) {
	switch strings.ToLower(s) {
	case "text":
		return FormatText, nil
	case "json":
		return FormatJSON, nil
	default:
		return FormatText, fmt.Errorf("unknown log format %q (want %q or %q)", s, "text", "json")
	}
}

// NewHandler builds the app's slog handler on out at the given level — the
// single choke point for format/stream (ADR-0006). An unknown Format is
// unrecoverable init-time configuration corruption and panics instead of
// silently degrading to text; ParseFormat and TelemetryConfig.Validate
// already reject unknown strings, so only a programming error can reach
// this branch. Never returns nil.
func NewHandler(level slog.Level, format Format, out io.Writer) slog.Handler {
	opts := &slog.HandlerOptions{Level: level}
	switch format {
	case FormatText:
		return slog.NewTextHandler(out, opts)
	case FormatJSON:
		return slog.NewJSONHandler(out, opts)
	default:
		panic(fmt.Sprintf("telemetry/log: unknown Format %v", format))
	}
}

// New returns a logger built on NewHandler.
func New(level slog.Level, format Format, out io.Writer) *slog.Logger {
	return slog.New(NewHandler(level, format, out))
}
