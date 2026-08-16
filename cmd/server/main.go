package main

import (
	"log/slog"
	"os"

	"github.com/Leesale99/league-tokens-backend/internal/infra/config"
	"github.com/Leesale99/league-tokens-backend/internal/infra/telemetry/log"
)

func main() {
	// Boot fallback: text handler on stdout at INFO (ADR-0006), so Load()'s
	// warnings, any fatal config error, and the boot confirmation always
	// surface regardless of LOG_LEVEL — the configured level isn't known
	// until config is parsed. Every handler comes from telemetry/log — the
	// single choke point for format/stream — so the two can only drift in
	// one place.
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

	// Configured handler: LOG_FORMAT selects text/json via log.ParseFormat
	// (ADR-0006: text in dev, JSON in production), wrapped in the context
	// decorator so ADR-0011 correlation fields and the service name land on
	// every emitted record.
	format, err := log.ParseFormat(cfg.Telemetry.LogFormat)
	if err != nil {
		// Defensive only — TelemetryConfig.Validate() already whitelists
		// LOG_FORMAT to text|json before MustLoad returns (ADR-0012
		// fast-fail: refuse to serve on bad config).
		boot.Error("invalid log format", "error", err, "log_format", cfg.Telemetry.LogFormat)
		os.Exit(1)
	}
	slog.SetDefault(slog.New(log.NewContextHandler(
		log.NewHandler(level, format, os.Stdout),
		log.ContextHandlerOptions{ServiceName: cfg.Telemetry.ServiceName},
	)))
	// TODO(#42): init the OTLP exporter from cfg.Telemetry (endpoint + token);
	// until tracing/metrics land, OTLP_ENDPOINT and otlp_token are validated
	// but unused.
}
