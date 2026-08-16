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

// ParseFormat maps a LOG_FORMAT-style string to a Format. It accepts "text"
// and "json" case-insensitively and errors otherwise — the same whitelist
// config.Validate() enforces for LOG_FORMAT (config task 01).
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

// NewHandler builds the app's slog handler on out at the given minimum
// level. It is the single choke point for format/stream: every handler the
// process uses comes from here, so the two can only drift in one place
// (ADR-0006). An unrecognized format falls back to text. Never returns nil.
func NewHandler(level slog.Level, format Format, out io.Writer) slog.Handler {
	opts := &slog.HandlerOptions{Level: level}
	if format == FormatJSON {
		return slog.NewJSONHandler(out, opts)
	}
	return slog.NewTextHandler(out, opts)
}

// New returns a logger built on NewHandler.
func New(level slog.Level, format Format, out io.Writer) *slog.Logger {
	return slog.New(NewHandler(level, format, out))
}
