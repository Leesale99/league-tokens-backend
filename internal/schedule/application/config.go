package application

import (
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	ProviderURL string `env:"SCHEDULE_PROVIDER_URL,required"`
	// ProviderAPIKey is loaded from the Docker secret "provider_api_key" by
	// infra/config.Load. It is deliberately not an env var (ADR-0012), so
	// ParseConfig leaves it empty and Validate only passes once the composer
	// has injected the secret.
	ProviderAPIKey string
	SyncInterval   time.Duration `env:"SCHEDULE_SYNC_INTERVAL" envDefault:"5m"`
}

func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse schedule config: %w", err)
	}
	return &cfg, nil
}

func (c *Config) Validate() error {
	var errs []string
	if c.ProviderURL == "" {
		errs = append(errs, "SCHEDULE_PROVIDER_URL is required")
	} else if _, err := url.Parse(c.ProviderURL); err != nil {
		errs = append(errs, fmt.Sprintf("SCHEDULE_PROVIDER_URL is invalid: %v", err))
	}
	if c.ProviderAPIKey == "" {
		errs = append(errs, "provider_api_key secret is required")
	}
	if c.SyncInterval <= 0 {
		errs = append(errs, "SCHEDULE_SYNC_INTERVAL must be positive")
	}
	if len(errs) > 0 {
		return fmt.Errorf("schedule config: %s", strings.Join(errs, "; "))
	}
	return nil
}
