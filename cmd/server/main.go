package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
)

func main() {
	cfg := config.MustLoad()

	// Structured slog per ADR-0006: text handler for dev, logs to stdout.
	// The JSON handler and correlation fields land with issue #41; the OTLP
	// exporter is issue #42.
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: cfg.Telemetry.LogLevelSlog(),
	})))
	// Self-describing even when LOG_LEVEL=warn/error would suppress an Info line.
	slog.Info("starting with valid config",
		"service", cfg.Telemetry.ServiceName,
		"log_level", cfg.Telemetry.LogLevelSlog().String())
}
