package application

import (
	"fmt"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"

	"github.com/Leesale99/league-tokens-backend/internal/infra/providerurl"
)

// Config holds feed-ingestion settings: the provider endpoint, poll cadence,
// and the insecure-http dev opt-in. ProviderAPIKey is injected separately by
// infra/config.Load (ADR-0012).
type Config struct {
	ProviderURL string `env:"FEED_PROVIDER_URL,required,notEmpty"`
	// AllowInsecureHTTP opts into plain http:// provider URLs for local
	// development against a mock provider. Defaults to false: the provider API
	// key is a Docker secret and must never travel in cleartext (ADR-0007).
	AllowInsecureHTTP bool `env:"FEED_ALLOW_INSECURE_HTTP" envDefault:"false"`
	// ProviderAPIKey is loaded from the Docker secret "provider_api_key" by
	// infra/config.Load. It is deliberately not an env var (ADR-0012), so
	// ParseConfig leaves it empty and Validate only passes once
	// infra/config.Load has injected the secret.
	ProviderAPIKey string
	// PollInterval is how often the feed adapter polls the provider. Defaults
	// to 1m; Validate rejects values below 1s.
	PollInterval time.Duration `env:"FEED_POLL_INTERVAL" envDefault:"1m"`
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
	// Normalize so the stored value is exactly what was validated; a pasted
	// trailing newline or leading space would otherwise fail at dial time in
	// the feed adapter (#17) after validation reported it valid.
	cfg.ProviderURL = strings.TrimSpace(cfg.ProviderURL)
	return &cfg, nil
}

// Validate checks the env-driven fields and the injected secret. Provider URL
// shape checks live in internal/infra/providerurl (shared with schedule).
func (c *Config) Validate() error {
	var errs []string
	if msg := providerurl.Validate(
		c.ProviderURL,
		"FEED_PROVIDER_URL",
		"FEED_ALLOW_INSECURE_HTTP",
		c.AllowInsecureHTTP,
	); msg != "" {
		errs = append(errs, msg)
	}
	if c.ProviderAPIKey == "" {
		errs = append(errs, "provider_api_key secret is required (injected by "+
			"infra/config.Load from /run/secrets/provider_api_key)")
	}
	if c.PollInterval < time.Second {
		errs = append(errs, "FEED_POLL_INTERVAL must be at least 1s")
	}
	if len(errs) > 0 {
		return fmt.Errorf("feed config: %s", strings.Join(errs, "; "))
	}
	return nil
}
