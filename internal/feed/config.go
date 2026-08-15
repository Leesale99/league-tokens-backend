package feed

import (
	"fmt"
	"net/url"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
)

type Config struct {
	ProviderURL string `env:"FEED_PROVIDER_URL,required"`
	// AllowInsecureHTTP opts into plain http:// provider URLs for local
	// development against a mock provider. Defaults to false: the provider API
	// key is a Docker secret and must never travel in cleartext (ADR-0007).
	AllowInsecureHTTP bool `env:"FEED_ALLOW_INSECURE_HTTP" envDefault:"false"`
	// ProviderAPIKey is loaded from the Docker secret "provider_api_key" by
	// infra/config.Load. It is deliberately not an env var (ADR-0012), so
	// ParseConfig leaves it empty and Validate only passes once
	// infra/config.Load has injected the secret.
	ProviderAPIKey string
	PollInterval   time.Duration `env:"FEED_POLL_INTERVAL" envDefault:"1m"`
}

// ParseConfig parses the env-driven fields of Config. Secret fields
// (ProviderAPIKey) are not env vars and remain empty here; they are injected by
// infra/config.Load before Validate runs. A Config produced by ParseConfig alone
// will not pass Validate until the secret has been set by infra/config.Load.
func ParseConfig() (*Config, error) {
	var cfg Config
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse feed config: %w", err)
	}
	return &cfg, nil
}

// Validate checks the env-driven fields and the injected secret. It rejects
// provider URLs that are missing, malformed, without a host, or non-http(s);
// plain http is rejected unless AllowInsecureHTTP opts in explicitly.
func (c *Config) Validate() error {
	var errs []string
	if c.ProviderURL == "" {
		errs = append(errs, "FEED_PROVIDER_URL is required")
	} else if u, err := url.Parse(c.ProviderURL); err != nil {
		errs = append(errs, fmt.Sprintf("FEED_PROVIDER_URL is invalid: %v", err))
	} else if u.Host == "" {
		errs = append(errs, "FEED_PROVIDER_URL must include a host")
	} else if u.Scheme == "http" && !c.AllowInsecureHTTP {
		errs = append(errs, "FEED_PROVIDER_URL must be https; set FEED_ALLOW_INSECURE_HTTP=true for local http dev")
	} else if u.Scheme != "https" && u.Scheme != "http" {
		errs = append(errs, "FEED_PROVIDER_URL must be http(s)")
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
