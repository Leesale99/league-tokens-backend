package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	// Boot fallback: text handler on stdout at INFO (ADR-0006), so Load()'s
	// warnings, any fatal config error, and the boot confirmation always
	// surface before config is parsed, on the same format as the rest of the
	// app.
	boot := slog.New(newTextHandler(slog.LevelInfo))
	slog.SetDefault(boot)

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()
	slog.SetDefault(slog.New(newTextHandler(level)))

	// Always-on boot confirmation (via the INFO boot handler): a healthy start
	// must be observable even when LOG_LEVEL=warn/error would filter the
	// configured handler. log_level reports the effective level for the rest
	// of the process.
	boot.Info("config loaded",
		"service", cfg.Telemetry.ServiceName,
		"log_level", level.String())
}

// newTextHandler builds the app's slog handler: text format on stdout
// (ADR-0006; issue #41 switches to JSON). The boot fallback and the
// config-driven handler share this so the format/stream can only drift in one
// place.
func newTextHandler(level slog.Level) slog.Handler {
	return slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})
}
