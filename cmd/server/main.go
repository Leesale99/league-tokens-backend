package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	// Boot logging deliberately uses Go's default slog handler (stderr, INFO
	// level): MustLoad runs first, so the cleartext-opt-in warning and any
	// fatal config error are always visible regardless of LOG_LEVEL. The
	// config-driven handler (stdout, configured level, ADR-0006) applies once
	// config is known. OTLP wiring is issue #42; JSON handler is issue #41.
	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()

	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: level,
	})))
	// Note: suppressed when LOG_LEVEL=warn/error — that filtering is expected;
	// the log_level attribute keeps the line self-describing when it appears.
	slog.Info("starting with valid config",
		"service", cfg.Telemetry.ServiceName,
		"log_level", level.String())
}
