package feed

import (
	"os"
	"strings"
	"testing"
	"time"
)

func TestConfigValidate(t *testing.T) {
	tests := []struct {
		name            string
		cfg             Config
		wantErr         bool
		errSubstr       string
		forbiddenSubstr string
	}{
		{
			name: "valid config",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "empty provider URL",
			cfg: Config{
				ProviderURL:    "",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL is required",
		},
		{
			name: "invalid provider URL",
			cfg: Config{
				ProviderURL:    "://invalid",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL is invalid",
		},
		{
			name: "non-http scheme",
			cfg: Config{
				ProviderURL:    "ftp://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL must be http(s)",
		},
		{
			name: "missing host",
			cfg: Config{
				ProviderURL:    "https://",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL must include a host",
		},
		{
			name: "plain http rejected without opt-in",
			cfg: Config{
				ProviderURL:    "http://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL must be https",
		},
		{
			name: "plain http allowed with opt-in",
			cfg: Config{
				ProviderURL:       "http://feed.example.com/v2",
				AllowInsecureHTTP: true,
				ProviderAPIKey:    "key-123",
				PollInterval:      1 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "embedded credentials rejected",
			cfg: Config{
				ProviderURL:    "https://user:pass@feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL must not contain embedded credentials",
		},
		{
			name: "uppercase https scheme accepted",
			cfg: Config{
				ProviderURL:    "HTTPS://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "uppercase http rejected without opt-in",
			cfg: Config{
				ProviderURL:    "HTTP://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL must be https",
		},
		{
			name: "port-only host rejected",
			cfg: Config{
				ProviderURL:    "https://:443/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL must include a host",
		},
		{
			name: "missing API key",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "provider_api_key secret is required",
		},
		{
			name: "zero poll interval",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   0,
			},
			wantErr:   true,
			errSubstr: "FEED_POLL_INTERVAL must be at least 1s",
		},
		{
			name: "negative poll interval",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   -5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_POLL_INTERVAL must be at least 1s",
		},
		{
			name: "tiny poll interval rejected",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Millisecond,
			},
			wantErr:   true,
			errSubstr: "FEED_POLL_INTERVAL must be at least 1s",
		},
		{
			name: "out-of-range port rejected",
			cfg: Config{
				ProviderURL:    "https://feed.example.com:99999/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL has an invalid port",
		},
		{
			name: "empty port rejected",
			cfg: Config{
				ProviderURL:    "https://feed.example.com:/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL has an invalid port",
		},
		{
			name: "parse error does not leak embedded credentials",
			cfg: Config{
				ProviderURL:    "https://user:pass@feed.example.com/%zz",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr:         true,
			errSubstr:       "FEED_PROVIDER_URL is invalid",
			forbiddenSubstr: "pass",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.cfg.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr = %v", err, tt.wantErr)
			}
			if tt.wantErr && tt.errSubstr != "" && err != nil && !strings.Contains(err.Error(), tt.errSubstr) {
				t.Errorf("Validate() error = %q, want substring %q", err, tt.errSubstr)
			}
			if tt.forbiddenSubstr != "" && err != nil && strings.Contains(err.Error(), tt.forbiddenSubstr) {
				t.Errorf("Validate() error leaks %q: %q", tt.forbiddenSubstr, err)
			}
		})
	}
}

func unsetEnv(t *testing.T, key string) {
	t.Helper()
	// unsetEnv mutates the process env; these tests must never run under
	// t.Parallel, or concurrent os.Setenv would race.
	old, existed := os.LookupEnv(key)
	if err := os.Unsetenv(key); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		var err error
		if existed {
			err = os.Setenv(key, old)
		} else {
			err = os.Unsetenv(key)
		}
		if err != nil {
			t.Errorf("restore env %s: %v", key, err)
		}
	})
}

func TestParseConfig(t *testing.T) {
	tests := []struct {
		name              string
		setup             func(t *testing.T)
		wantURL           string
		wantPoll          time.Duration
		wantAllowInsecure bool
		wantErr           bool
		errSubstr         string
	}{
		{
			name: "missing required provider URL",
			setup: func(t *testing.T) {
				unsetEnv(t, "FEED_PROVIDER_URL")
			},
			wantErr:   true,
			errSubstr: "FEED_PROVIDER_URL",
		},
		{
			name: "invalid poll interval",
			setup: func(t *testing.T) {
				t.Setenv("FEED_PROVIDER_URL", "https://feed.example.com/v2")
				t.Setenv("FEED_POLL_INTERVAL", "abc")
			},
			wantErr:   true,
			errSubstr: "parse feed config",
		},
		{
			name: "valid",
			setup: func(t *testing.T) {
				t.Setenv("FEED_PROVIDER_URL", "https://feed.example.com/v2")
				t.Setenv("FEED_POLL_INTERVAL", "30s")
			},
			wantURL:  "https://feed.example.com/v2",
			wantPoll: 30 * time.Second,
		},
		{
			name: "poll interval default",
			setup: func(t *testing.T) {
				t.Setenv("FEED_PROVIDER_URL", "https://feed.example.com/v2")
				unsetEnv(t, "FEED_POLL_INTERVAL")
			},
			wantURL:  "https://feed.example.com/v2",
			wantPoll: time.Minute,
		},
		{
			name: "insecure http opt-in flag",
			setup: func(t *testing.T) {
				t.Setenv("FEED_PROVIDER_URL", "http://feed.example.com/v2")
				t.Setenv("FEED_ALLOW_INSECURE_HTTP", "true")
			},
			wantURL:           "http://feed.example.com/v2",
			wantPoll:          time.Minute,
			wantAllowInsecure: true,
		},
		{
			name: "insecure http opt-in defaults to false",
			setup: func(t *testing.T) {
				t.Setenv("FEED_PROVIDER_URL", "https://feed.example.com/v2")
			},
			wantURL:           "https://feed.example.com/v2",
			wantPoll:          time.Minute,
			wantAllowInsecure: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.setup(t)
			cfg, err := ParseConfig()
			if (err != nil) != tt.wantErr {
				t.Fatalf("ParseConfig() error = %v, wantErr = %v", err, tt.wantErr)
			}
			if tt.wantErr {
				if err != nil && tt.errSubstr != "" && !strings.Contains(err.Error(), tt.errSubstr) {
					t.Errorf("ParseConfig() error = %q, want substring %q", err, tt.errSubstr)
				}
				return
			}
			if cfg.ProviderURL != tt.wantURL {
				t.Errorf("ProviderURL = %q, want %q", cfg.ProviderURL, tt.wantURL)
			}
			if cfg.PollInterval != tt.wantPoll {
				t.Errorf("PollInterval = %v, want %v", cfg.PollInterval, tt.wantPoll)
			}
			if cfg.ProviderAPIKey != "" {
				t.Errorf("ProviderAPIKey = %q, want empty (injected by infra/config.Load)", cfg.ProviderAPIKey)
			}
			if cfg.AllowInsecureHTTP != tt.wantAllowInsecure {
				t.Errorf("AllowInsecureHTTP = %v, want %v", cfg.AllowInsecureHTTP, tt.wantAllowInsecure)
			}
		})
	}
}
