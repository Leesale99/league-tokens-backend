package config

import (
	"errors"
	"fmt"
	"log"
	"strings"

	gamecfg "github.com/Leesale99/league-tokens-backend/internal/game/application"
	identitycfg "github.com/Leesale99/league-tokens-backend/internal/identity/application"
	ledgercfg "github.com/Leesale99/league-tokens-backend/internal/ledger/application"
	schedulecfg "github.com/Leesale99/league-tokens-backend/internal/schedule/application"
	feedcfg "github.com/Leesale99/league-tokens-backend/internal/feed"
)

type ComposerConfig struct {
	Postgres  *PostgresConfig
	HTTP      *HTTPConfig
	Telemetry *TelemetryConfig
	Identity  *identitycfg.Config
	Game      *gamecfg.Config
	Ledger    *ledgercfg.Config
	Schedule  *schedulecfg.Config
	Feed      *feedcfg.Config
}

func Load() (*ComposerConfig, error) {
	postgres, err := parsePostgresConfig()
	if err != nil {
		return nil, err
	}

	httpCfg, err := parseHTTPConfig()
	if err != nil {
		return nil, err
	}

	telemetry, err := parseTelemetryConfig()
	if err != nil {
		return nil, err
	}

	identity, err := identitycfg.ParseConfig()
	if err != nil {
		return nil, err
	}

	game, err := gamecfg.ParseConfig()
	if err != nil {
		return nil, err
	}

	ledger, err := ledgercfg.ParseConfig()
	if err != nil {
		return nil, err
	}

	schedule, err := schedulecfg.ParseConfig()
	if err != nil {
		return nil, err
	}

	feed, err := feedcfg.ParseConfig()
	if err != nil {
		return nil, err
	}

	if err := loadSecrets(postgres, telemetry, identity, schedule, feed); err != nil {
		return nil, fmt.Errorf("load secrets: %w", err)
	}

	if err := validateAll(postgres, httpCfg, telemetry, identity, game, ledger, schedule, feed); err != nil {
		return nil, err
	}

	return &ComposerConfig{
		Postgres:  postgres,
		HTTP:      httpCfg,
		Telemetry: telemetry,
		Identity:  identity,
		Game:      game,
		Ledger:    ledger,
		Schedule:  schedule,
		Feed:      feed,
	}, nil
}

func MustLoad() *ComposerConfig {
	cfg, err := Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	return cfg
}

func loadSecrets(postgres *PostgresConfig, telemetry *TelemetryConfig,
	identity *identitycfg.Config, schedule *schedulecfg.Config, feed *feedcfg.Config,
) error {
	var errs []string

	if pwd, err := ReadSecret("pg_password"); err != nil {
		errs = append(errs, fmt.Sprintf("pg_password: %v", err))
	} else {
		postgres.password = pwd
	}

	if token, err := ReadSecret("otlp_token"); err != nil {
		errs = append(errs, fmt.Sprintf("otlp_token: %v", err))
	} else {
		telemetry.OTLPToken = token
	}

	if key, err := ReadSecret("jwt_signing_key"); err != nil {
		errs = append(errs, fmt.Sprintf("jwt_signing_key: %v", err))
	} else {
		identity.JWTSigningKeyED25519 = key
	}

	if key, err := ReadSecret("provider_api_key"); err != nil {
		errs = append(errs, fmt.Sprintf("provider_api_key: %v", err))
	} else {
		schedule.ProviderAPIKey = key
		feed.ProviderAPIKey = key
	}

	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "; "))
	}
	return nil
}

func validateAll(configs ...interface{ Validate() error }) error {
	var errs []string
	for _, cfg := range configs {
		if err := cfg.Validate(); err != nil {
			errs = append(errs, err.Error())
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("config validation failed:\n  %s", strings.Join(errs, "\n  "))
	}
	return nil
}
