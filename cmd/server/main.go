package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	// Boot fallback: text handler on stdout at INFO (ADR-0006), so Load()'s
	// warnings, any fatal config error, and the boot confirmation always
	// surface regardless of LOG_LEVEL — the configured level isn't known
	// until config is parsed.
	boot := slog.New(newTextHandler(slog.LevelInfo))
	slog.SetDefault(boot)

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()

	// Emit the always-on boot confirmation while boot is still the default
	// logger, then swap to the configured-level handler for everything after.
	// log_level reports the effective level for the rest of the process.
	boot.Info("config loaded",
		"service", cfg.Telemetry.ServiceName,
		"log_level", level.String())
	slog.SetDefault(slog.New(newTextHandler(level)))
	// TODO(#42): init the OTLP exporter from cfg.Telemetry (endpoint + token);
	// until tracing/metrics land, OTLP_ENDPOINT and otlp_token are validated
	// but unused.
}

// newTextHandler builds the app's slog handler: text format on stdout
// (ADR-0006; issue #41 switches to JSON). The boot fallback and the
// config-driven handler share this so the format/stream can only drift in one
// place.
func newTextHandler(level slog.Level) slog.Handler {
	return slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})
}
