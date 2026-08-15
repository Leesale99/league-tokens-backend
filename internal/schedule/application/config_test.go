package application

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
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "empty provider URL",
			cfg: Config{
				ProviderURL:    "",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "invalid provider URL",
			cfg: Config{
				ProviderURL:    "://invalid",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "non-http scheme",
			cfg: Config{
				ProviderURL:    "ftp://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "missing host",
			cfg: Config{
				ProviderURL:    "https://",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "missing API key",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: true,
		},
		{
			name: "zero sync interval",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   0,
			},
			wantErr: true,
		},
		{
			name: "negative sync interval",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   -1 * time.Minute,
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
		wantSync  time.Duration
		wantErr   bool
		errSubstr string
	}{
		{
			name: "missing required provider URL",
			setup: func(t *testing.T) {
				unsetEnv(t, "SCHEDULE_PROVIDER_URL")
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL",
		},
		{
			name: "invalid sync interval",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				t.Setenv("SCHEDULE_SYNC_INTERVAL", "abc")
			},
			wantErr:   true,
			errSubstr: "parse schedule config",
		},
		{
			name: "valid",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				t.Setenv("SCHEDULE_SYNC_INTERVAL", "10m")
			},
			wantURL:  "https://api.example.com/v1",
			wantSync: 10 * time.Minute,
		},
		{
			name: "sync interval default",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
			},
			wantURL:  "https://api.example.com/v1",
			wantSync: 5 * time.Minute,
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
			if cfg.SyncInterval != tt.wantSync {
				t.Errorf("SyncInterval = %v, want %v", cfg.SyncInterval, tt.wantSync)
			}
			if cfg.ProviderAPIKey != "" {
				t.Errorf("ProviderAPIKey = %q, want empty (injected by infra/config.Load)", cfg.ProviderAPIKey)
			}
		})
	}
}
