package feed

import (
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	ProviderURL    string        `env:"FEED_PROVIDER_URL,required"`
	ProviderAPIKey string
	PollInterval   time.Duration `env:"FEED_POLL_INTERVAL" envDefault:"1m"`
}

func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse feed config: %w", err)
	}
	return &cfg, nil
}

func (c *Config) Validate() error {
	var errs []string
	if c.ProviderURL == "" {
		errs = append(errs, "FEED_PROVIDER_URL is required")
	} else if _, err := url.Parse(c.ProviderURL); err != nil {
		errs = append(errs, fmt.Sprintf("FEED_PROVIDER_URL is invalid: %v", err))
	}
	if c.ProviderAPIKey == "" {
		errs = append(errs, "provider_api_key secret is required")
	}
	if c.PollInterval <= 0 {
		errs = append(errs, "FEED_POLL_INTERVAL must be positive")
	}
	if len(errs) > 0 {
		return fmt.Errorf("feed config: %s", strings.Join(errs, "; "))
	}
	return nil
}
