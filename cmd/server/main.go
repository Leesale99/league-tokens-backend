package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	// Boot fallback: text handler on stdout at INFO (ADR-0006), so Load()'s
	// warnings and any fatal config error always surface before config is
	// parsed, on the same format as the rest of the app.
	slog.SetDefault(slog.New(newTextHandler(slog.LevelInfo)))

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()
	slog.SetDefault(slog.New(newTextHandler(level)))

	// Note: suppressed when LOG_LEVEL=warn/error — expected filtering; the
	// log_level attribute keeps the line self-describing when it appears.
	slog.Info("config loaded",
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
