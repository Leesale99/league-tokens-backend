package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
	"github.com/Leesale99/league-tokens-backend/internal/infra/telemetry/log"
)

func main() {
	// Startup sequence: install a text/INFO fallback for config diagnostics,
	// load config, emit a format-aware confirmation, then install the
	// configured application logger.
	fallbackLogger := slog.New(log.NewHandler(slog.LevelInfo, log.FormatText, os.Stdout))
	slog.SetDefault(fallbackLogger)

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()

	// MustLoad validates LOG_FORMAT before returning, but keep the parse error
	// local so future drift cannot silently fall back to text logging.
	format, err := log.ParseFormat(cfg.Telemetry.LogFormat)
	if err != nil {
		fallbackLogger.Error("invalid log format", slog.Any("error", err))
		os.Exit(1)
	}

	// Keep boot confirmation visible even when LOG_LEVEL is warn/error, while
	// honoring the configured output format for production JSON collectors.
	bootLogger := slog.New(log.NewHandler(slog.LevelInfo, format, os.Stdout))
	bootLogger.Info("config loaded",
		slog.String("service", cfg.Telemetry.ServiceName),
		slog.String("log_level", level.String()),
		slog.String("log_format", cfg.Telemetry.LogFormat))

	applicationLogger := log.NewConfigured(level, format, cfg.Telemetry.ServiceName, os.Stdout)
	slog.SetDefault(applicationLogger)
	// TODO(#42): init the OTLP exporter from cfg.Telemetry; until then
	// OTLP_ENDPOINT/otlp_token are validated but unused.
}
