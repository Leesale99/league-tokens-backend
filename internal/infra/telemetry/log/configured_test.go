package log

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"strings"
	"testing"
)

// TestNewConfigured exercises the exact boot chain main() uses (handler
// factory → correlation decorator → default), so a future wiring regression
// — e.g. the decorator being dropped or an unknown format silently falling
// back to text — fails in tests, not in production logs.
func TestNewConfigured(t *testing.T) {
	var buf bytes.Buffer
	logger := NewConfigured(slog.LevelInfo, FormatJSON, "league-tokens-test", &buf)

	logger.Info("match resolved", Op("game.ResolveMatch"))

	var m map[string]any
	if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
		t.Fatalf("configured logger emitted invalid JSON: %v", err)
	}
	if got := m["service"]; got != "league-tokens-test" {
		t.Errorf("service = %q, want %q (decorator must survive the boot chain)", got, "league-tokens-test")
	}
	if got := m["msg"]; got != "match resolved" {
		t.Errorf("msg = %q, want %q", got, "match resolved")
	}
}

// TestNewConfiguredText asserts the same chain in text format (identical
// field keys across formats, matching ADR-0006 dev/prod behavior).
func TestNewConfiguredText(t *testing.T) {
	var buf bytes.Buffer
	logger := NewConfigured(slog.LevelInfo, FormatText, "league-tokens-test", &buf)
	logger.Info("booted")

	out := buf.String()
	for _, want := range []string{`msg=booted`, "service=league-tokens-test"} {
		if !strings.Contains(out, want) {
			t.Errorf("text output %q missing %q", out, want)
		}
	}
}

// TestNewConfiguredInvalidServiceName asserts the constructor chain fails
// fast on an invalid non-empty service name, consistent with
// NewContextHandler's contract.
func TestNewConfiguredInvalidServiceName(t *testing.T) {
	defer func() {
		if recover() == nil {
			t.Error("NewConfigured with an over-long service name did not panic")
		}
	}()
	NewConfigured(slog.LevelInfo, FormatText, strings.Repeat("a", maxCorrelationIDLen+1), io.Discard)
}
