package application

import (
	"fmt"

	"github.com/caarlos0/env/v11"
)

// Config holds ledger-domain settings. No env vars exist at Launch, so this
// struct is intentionally empty; ParseConfig and Validate are no-ops until
// fields are added (see compose.env.example).
type Config struct {
}

// ParseConfig parses the env-driven fields of Config. It is currently a no-op:
// the ledger context has no env-driven settings at Launch.
func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse ledger config: %w", err)
	}
	return &cfg, nil
}

// Validate currently accepts any Config; it will gain real checks once the
// ledger context gains configuration fields.
func (c *Config) Validate() error {
	return nil
}
