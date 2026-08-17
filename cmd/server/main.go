package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
	"github.com/Leesale99/league-tokens-backend/internal/infra/telemetry/log"
)

func main() {
	// Startup sequence: install a text/INFO fallback for config diagnostics,
	// load config, emit confirmation, then install the configured logger.
	startupLogger := slog.New(log.NewHandler(slog.LevelInfo, log.FormatText, os.Stdout))
	slog.SetDefault(startupLogger)

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()

	format, err := log.ParseFormat(cfg.Telemetry.LogFormat)
	if err != nil {
		startupLogger.Error("invalid log format",
			slog.Any("error", err),
			slog.String("log_format", cfg.Telemetry.LogFormat))
		os.Exit(1)
	}

	// The confirmation remains text; log_format reports the final format.
	startupLogger.Info("config loaded",
		slog.String("service", cfg.Telemetry.ServiceName),
		slog.String("log_level", level.String()),
		slog.String("log_format", cfg.Telemetry.LogFormat))

	options := log.ContextHandlerOptions{ServiceName: cfg.Telemetry.ServiceName}

	applicationLogger := slog.New(log.NewContextHandler(
		log.NewHandler(level, format, os.Stdout),
		options,
	))
	slog.SetDefault(applicationLogger)
	// TODO(#42): init the OTLP exporter from cfg.Telemetry; until then
	// OTLP_ENDPOINT/otlp_token are validated but unused.
}
