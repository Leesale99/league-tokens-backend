package feed

import (
	"os"
	"strings"
	"testing"
	"time"
)

func TestConfigValidate(t *testing.T) {
	tests := []struct {
		name    string
		cfg     Config
		wantErr bool
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
			wantErr: true,
		},
		{
			name: "invalid provider URL",
			cfg: Config{
				ProviderURL:    "://invalid",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "non-http scheme",
			cfg: Config{
				ProviderURL:    "ftp://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "missing host",
			cfg: Config{
				ProviderURL:    "https://",
				ProviderAPIKey: "key-123",
				PollInterval:   1 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "missing API key",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "",
				PollInterval:   1 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "zero poll interval",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   0,
			},
			wantErr: true,
		},
		{
			name: "negative poll interval",
			cfg: Config{
				ProviderURL:    "https://feed.example.com/v2",
				ProviderAPIKey: "key-123",
				PollInterval:   -5 * time.Minute,
			},
			wantErr: true,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := tt.cfg.Validate()
			if (err != nil) != tt.wantErr {
				t.Errorf("Validate() error = %v, wantErr = %v", err, tt.wantErr)
			}
		})
	}
}

func unsetEnv(t *testing.T, key string) {
	t.Helper()
	old, existed := os.LookupEnv(key)
	if err := os.Unsetenv(key); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if existed {
			_ = os.Setenv(key, old)
		} else {
			_ = os.Unsetenv(key)
		}
	})
}

func TestParseConfig(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(t *testing.T)
		wantURL   string
		wantPoll  time.Duration
		wantErr   bool
		errSubstr string
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
		})
	}
}
