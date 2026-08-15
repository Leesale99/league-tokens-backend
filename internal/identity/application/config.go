package application

import (
	"fmt"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	SessionTTL time.Duration `env:"SESSION_TTL" envDefault:"24h"`
	// JWTSigningKeyED25519 is loaded from the Docker secret "jwt_signing_key"
	// by infra/config.Load. It is deliberately not an env var (ADR-0012), so
	// ParseConfig leaves it empty and Validate only passes once the composer
	// has injected the secret.
	JWTSigningKeyED25519 string
}

// ParseConfig parses the env-driven fields of Config. Secrets such as
// JWTSigningKeyED25519 are injected by infra/config.Load, so a Config produced
// here alone will not pass Validate.
func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse identity config: %w", err)
	}
	return &cfg, nil
}

// Validate checks the env-driven fields and the injected secret. A Config must
// have JWTSigningKeyED25519 injected by infra/config.Load before Validate can
// pass.
func (c *Config) Validate() error {
	var errs []string
	if c.SessionTTL <= 0 {
		errs = append(errs, "SESSION_TTL must be positive")
	}
	if c.JWTSigningKeyED25519 == "" {
		errs = append(errs, "jwt_signing_key secret is required")
	}
	if len(errs) > 0 {
		return fmt.Errorf("identity config: %s", strings.Join(errs, "; "))
	}
	return nil
}
