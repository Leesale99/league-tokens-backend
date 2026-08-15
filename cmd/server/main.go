package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	// Fallback handler used until config is loaded: text, stdout, INFO. Boot
	// logging (the cleartext-opt-in warning from Load and any fatal config
	// error) therefore always shows — Warn/Error pass the INFO level — on the
	// same stream and format as the rest of the app (ADR-0006). Once config is
	// known the handler is rebuilt with the configured LOG_LEVEL. OTLP wiring
	// is issue #42; JSON handler is issue #41.
	slog.SetDefault(slog.New(newTextHandler(slog.LevelInfo)))

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()
	slog.SetDefault(slog.New(newTextHandler(level)))

	// Note: suppressed when LOG_LEVEL=warn/error — that filtering is expected;
	// the log_level attribute keeps the line self-describing when it appears.
	slog.Info("starting with valid config",
		"service", cfg.Telemetry.ServiceName,
		"log_level", level.String())
}

// newTextHandler builds the app's slog handler: text format on stdout
// (ADR-0006). The boot fallback and the config-driven handler share this so
// the format/stream can only drift in one place (issue #41 switches to JSON).
func newTextHandler(level slog.Level) slog.Handler {
	return slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})
}
