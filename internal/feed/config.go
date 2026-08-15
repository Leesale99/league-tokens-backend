package feed

import (
	"errors"
	"fmt"
	"net/url"
	"strconv"
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

// parseErrorReason returns the underlying reason of a url.Parse failure,
// omitting the raw URL that url.Error embeds (which may carry userinfo).
func parseErrorReason(err error) string {
	var ue *url.Error
	if errors.As(err, &ue) && ue.Err != nil {
		return ue.Err.Error()
	}
	return err.Error()
}

func validPort(p string) bool {
	n, err := strconv.Atoi(p)
	return err == nil && n >= 1 && n <= 65535
}

// invalidURLPort reports whether u carries a malformed or out-of-range port,
// e.g. "https://host:99999/" or "https://host:/".
func invalidURLPort(u *url.URL) bool {
	if strings.HasSuffix(u.Host, ":") {
		return true
	}
	if p := u.Port(); p != "" && !validPort(p) {
		return true
	}
	return false
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
// provider URLs that are missing, malformed, without a host, with embedded
// credentials, with an invalid port, or non-http(s); plain http is rejected
// unless AllowInsecureHTTP opts in explicitly.
func (c *Config) Validate() error {
	var errs []string
	if c.ProviderURL == "" {
		errs = append(errs, "FEED_PROVIDER_URL is required")
	} else {
		u, err := url.Parse(c.ProviderURL)
		switch {
		case err != nil:
			// url.Parse errors embed the raw URL (url.Error.URL), which may
			// carry userinfo; surface only the reason so credentials never
			// reach the logs (ADR-0007).
			errs = append(errs, fmt.Sprintf("FEED_PROVIDER_URL is invalid: %s", parseErrorReason(err)))
		case u.Host == "" || u.Hostname() == "":
			errs = append(errs, "FEED_PROVIDER_URL must include a host")
		case u.User != nil:
			errs = append(errs, "FEED_PROVIDER_URL must not contain embedded credentials (user:pass@)")
		case invalidURLPort(u):
			errs = append(errs, "FEED_PROVIDER_URL has an invalid port")
		case strings.EqualFold(u.Scheme, "http") && !c.AllowInsecureHTTP:
			errs = append(errs, "FEED_PROVIDER_URL must be https; set FEED_ALLOW_INSECURE_HTTP=true for local http dev")
		case !strings.EqualFold(u.Scheme, "https") && !strings.EqualFold(u.Scheme, "http"):
			errs = append(errs, "FEED_PROVIDER_URL must be http(s)")
		}
	}
	if c.ProviderAPIKey == "" {
		errs = append(errs, "provider_api_key secret is required (injected by infra/config.Load from /run/secrets/provider_api_key)")
	}
	if c.PollInterval < time.Second {
		errs = append(errs, "FEED_POLL_INTERVAL must be at least 1s")
	}
	if len(errs) > 0 {
		return fmt.Errorf("feed config: %s", strings.Join(errs, "; "))
	}
	return nil
}
