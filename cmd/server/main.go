package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
	"github.com/Leesale99/league-tokens-backend/internal/infra/telemetry/log"
)

func main() {
	// Boot fallback: text handler at INFO (ADR-0006) so config-load
	// diagnostics always surface — the configured level isn't known yet.
	// All handlers come from telemetry/log: one choke point for format/stream.
	boot := slog.New(log.NewHandler(slog.LevelInfo, log.FormatText, os.Stdout))
	slog.SetDefault(boot)

	cfg := config.MustLoad()
	level := cfg.Telemetry.LogLevelSlog()

	// Emit the always-on boot confirmation while boot is still the default
	// logger, then swap to the configured-level handler for everything after.
	// log_level reports the effective level for the rest of the process.
	boot.Info("config loaded",
		"service", cfg.Telemetry.ServiceName,
		"log_level", level.String())

	// Swap to the configured level/format (ADR-0006: text dev, JSON prod),
	// wrapped in the context decorator so correlation fields and the
	// service name land on every record.
	format, err := log.ParseFormat(cfg.Telemetry.LogFormat)
	if err != nil {
		// Defensive: Validate() already whitelisted LOG_FORMAT
		// (ADR-0012 fast-fail).
		boot.Error("invalid log format", "error", err, "log_format", cfg.Telemetry.LogFormat)
		os.Exit(1)
	}
	slog.SetDefault(slog.New(log.NewContextHandler(
		log.NewHandler(level, format, os.Stdout),
		log.ContextHandlerOptions{ServiceName: cfg.Telemetry.ServiceName},
	)))
	// TODO(#42): init the OTLP exporter from cfg.Telemetry; until then
	// OTLP_ENDPOINT/otlp_token are validated but unused.
}
