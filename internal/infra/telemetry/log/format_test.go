package log

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"strings"
	"testing"
)

func TestParseFormat(t *testing.T) {
	tests := []struct {
		name    string
		in      string
		want    Format
		wantErr bool
	}{
		{"text lowercase", "text", FormatText, false},
		{"json lowercase", "json", FormatJSON, false},
		{"text uppercase", "TEXT", FormatText, false},
		{"json mixed case", "Json", FormatJSON, false},
		{"empty", "", FormatText, true},
		{"invalid", "yaml", FormatText, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseFormat(tt.in)
			if (err != nil) != tt.wantErr {
				t.Errorf("ParseFormat(%q) error = %v, wantErr = %v", tt.in, err, tt.wantErr)
				return
			}
			if got != tt.want {
				t.Errorf("ParseFormat(%q) = %v, want %v", tt.in, got, tt.want)
			}
		})
	}
}

// TestNewHandlerJSON asserts the JSON handler's output is parseable JSON
// carrying msg, level, and the emitted attrs.
func TestNewHandlerJSON(t *testing.T) {
	var buf bytes.Buffer
	logger := New(slog.LevelInfo, FormatJSON, &buf)
	logger.Info("match resolved", Op("game.ResolveMatch"), "round", 14)

	var m map[string]any
	if err := json.Unmarshal(buf.Bytes(), &m); err != nil {
		t.Fatalf("JSON handler emitted invalid JSON: %v (line %q)", err, buf.String())
	}
	if got := m["msg"]; got != "match resolved" {
		t.Errorf("msg = %q, want %q", got, "match resolved")
	}
	if got := m["level"]; got != "INFO" {
		t.Errorf("level = %q, want %q", got, "INFO")
	}
	if got := m["op"]; got != "game.ResolveMatch" {
		t.Errorf("op = %q, want %q", got, "game.ResolveMatch")
	}
	if got := m["round"]; got != float64(14) {
		t.Errorf("round = %v, want 14", got)
	}
}

// TestNewHandlerText asserts the text handler emits human-readable text on
// the same attrs (identical field keys across formats).
func TestNewHandlerText(t *testing.T) {
	var buf bytes.Buffer
	logger := New(slog.LevelInfo, FormatText, &buf)
	logger.Info("match resolved", Op("game.ResolveMatch"), "round", 14)

	out := buf.String()
	for _, want := range []string{`msg="match resolved"`, "level=INFO", "op=game.ResolveMatch", "round=14"} {
		if !strings.Contains(out, want) {
			t.Errorf("text output %q missing %q", out, want)
		}
	}
}

func TestNewHandlerLevelFiltering(t *testing.T) {
	var buf bytes.Buffer
	logger := New(slog.LevelInfo, FormatJSON, &buf)

	logger.Debug("debug should be suppressed")
	if buf.Len() != 0 {
		t.Errorf("debug record emitted at info level: %q", buf.String())
	}

	logger.Info("info should pass")
	if buf.Len() == 0 {
		t.Error("info record not emitted at info level")
	}
}

func TestOp(t *testing.T) {
	tests := []struct {
		name string
		op   string
	}{
		{"game prefix", "game.ResolveMatch"},
		{"config prefix", "config.Load"},
		{"infra prefix", "infra.idempotency_conflict"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			attr := Op(tt.op)
			if attr.Key != "op" {
				t.Errorf("Op() key = %q, want %q", attr.Key, "op")
			}
			if got := attr.Value.String(); got != tt.op {
				t.Errorf("Op() value = %q, want %q", got, tt.op)
			}
		})
	}
}
