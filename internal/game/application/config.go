package application

import (
	"fmt"

	"github.com/caarlos0/env/v11"
)

// Config holds game-domain settings. It has no env-driven fields yet, so
// ParseConfig and Validate are no-ops until fields are added (see
// compose.env.example).
type Config struct{}

// ParseConfig parses the env-driven fields of Config. It is currently a no-op:
// the game context has no env-driven settings yet.
func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse game config: %w", err)
	}
	return &cfg, nil
}

// Validate currently accepts any Config; it will gain real checks once the game
// context gains configuration fields.
func (c *Config) Validate() error {
	return nil
}
