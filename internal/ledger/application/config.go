package application

import (
	"github.com/caarlos0/env/v11"
)

type Config struct {
}

func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse ledger config: %w", err)
	}
	return &cfg, nil
}

func (c *Config) Validate() error {
	return nil
}
