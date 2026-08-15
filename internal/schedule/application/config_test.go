package application

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
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL is required",
		},
		{
			name: "invalid provider URL",
			cfg: Config{
				ProviderURL:    "://invalid",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL is invalid",
		},
		{
			name: "non-http scheme",
			cfg: Config{
				ProviderURL:    "ftp://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must be http(s)",
		},
		{
			name: "missing host",
			cfg: Config{
				ProviderURL:    "https://",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must include a host",
		},
		{
			name: "plain http rejected without opt-in",
			cfg: Config{
				ProviderURL:    "http://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must be https",
		},
		{
			name: "plain http allowed with opt-in",
			cfg: Config{
				ProviderURL:       "http://api.example.com/v1",
				AllowInsecureHTTP: true,
				ProviderAPIKey:    "key-123",
				SyncInterval:      5 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "embedded credentials rejected",
			cfg: Config{
				ProviderURL:    "https://user:pass@api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must not contain embedded credentials",
		},
		{
			name: "uppercase https scheme accepted",
			cfg: Config{
				ProviderURL:    "HTTPS://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "uppercase http rejected without opt-in",
			cfg: Config{
				ProviderURL:    "HTTP://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must be https",
		},
		{
			name: "port-only host rejected",
			cfg: Config{
				ProviderURL:    "https://:443/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must include a host",
		},
		{
			name: "missing API key",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "provider_api_key secret is required",
		},
		{
			name: "zero sync interval",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   0,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_SYNC_INTERVAL must be at least 1s",
		},
		{
			name: "negative sync interval",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   -1 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_SYNC_INTERVAL must be at least 1s",
		},
		{
			name: "tiny sync interval rejected",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   1 * time.Millisecond,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_SYNC_INTERVAL must be at least 1s",
		},
		{
			name: "exactly one second sync interval accepted",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   time.Second,
			},
			wantErr: false,
		},
		{
			name: "one second minus a nanosecond rejected",
			cfg: Config{
				ProviderURL:    "https://api.example.com/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   time.Second - time.Nanosecond,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_SYNC_INTERVAL must be at least 1s",
		},
		{
			name: "out-of-range port rejected",
			cfg: Config{
				ProviderURL:    "https://api.example.com:99999/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL has an invalid port",
		},
		{
			name: "empty port rejected",
			cfg: Config{
				ProviderURL:    "https://api.example.com:/v1",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL has an invalid port",
		},
		{
			name: "opt-in does not relax scheme whitelist",
			cfg: Config{
				ProviderURL:       "ftp://api.example.com/v1",
				AllowInsecureHTTP: true,
				ProviderAPIKey:    "key-123",
				SyncInterval:      5 * time.Minute,
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL must be http(s)",
		},
		{
			name: "whitespace-padded URL tolerated",
			cfg: Config{
				ProviderURL:    "  https://api.example.com/v1\n",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr: false,
		},
		{
			name: "parse error does not leak embedded credentials",
			cfg: Config{
				ProviderURL:    "https://user:pass@api.example.com/%zz",
				ProviderAPIKey: "key-123",
				SyncInterval:   5 * time.Minute,
			},
			wantErr:         true,
			errSubstr:       "SCHEDULE_PROVIDER_URL is invalid",
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

func TestConfigValidateMultipleErrors(t *testing.T) {
	// All three checks fire at once (empty URL, missing key, zero interval) so
	// the strings.Join accumulation branch is exercised, not just single-error
	// cases.
	err := (&Config{}).Validate()
	if err == nil {
		t.Fatal("Validate() = nil, want error")
	}
	for _, s := range []string{
		"SCHEDULE_PROVIDER_URL is required",
		"provider_api_key secret is required",
		"SCHEDULE_SYNC_INTERVAL must be at least 1s",
	} {
		if !strings.Contains(err.Error(), s) {
			t.Errorf("Validate() error = %q, want substring %q", err, s)
		}
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
		wantSync          time.Duration
		wantAllowInsecure bool
		wantErr           bool
		errSubstr         string
	}{
		{
			name: "missing required provider URL",
			setup: func(t *testing.T) {
				unsetEnv(t, "SCHEDULE_PROVIDER_URL")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantErr:   true,
			errSubstr: "SCHEDULE_PROVIDER_URL",
		},
		{
			name: "set-but-empty provider URL rejected at parse",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantErr:   true,
			errSubstr: "should not be empty",
		},
		{
			name: "invalid sync interval",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				t.Setenv("SCHEDULE_SYNC_INTERVAL", "abc")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantErr:   true,
			errSubstr: "parse schedule config",
		},
		{
			name: "invalid insecure http flag",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				t.Setenv("SCHEDULE_ALLOW_INSECURE_HTTP", "banana")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
			},
			wantErr:   true,
			errSubstr: "parse schedule config",
		},
		{
			name: "provider URL whitespace normalized",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "  https://api.example.com/v1\n")
				t.Setenv("SCHEDULE_SYNC_INTERVAL", "5m")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantURL:  "https://api.example.com/v1",
			wantSync: 5 * time.Minute,
		},
		{
			name: "whitespace-only provider URL normalized to empty",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "   ")
				t.Setenv("SCHEDULE_SYNC_INTERVAL", "5m")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantURL:  "",
			wantSync: 5 * time.Minute,
		},
		{
			name: "valid",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				t.Setenv("SCHEDULE_SYNC_INTERVAL", "10m")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantURL:  "https://api.example.com/v1",
			wantSync: 10 * time.Minute,
		},
		{
			name: "sync interval default",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
			},
			wantURL:  "https://api.example.com/v1",
			wantSync: 5 * time.Minute,
		},
		{
			name: "insecure http opt-in flag",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "http://api.example.com/v1")
				t.Setenv("SCHEDULE_ALLOW_INSECURE_HTTP", "true")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
			},
			wantURL:           "http://api.example.com/v1",
			wantSync:          5 * time.Minute,
			wantAllowInsecure: true,
		},
		{
			name: "insecure http opt-in defaults to false",
			setup: func(t *testing.T) {
				t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
				unsetEnv(t, "SCHEDULE_ALLOW_INSECURE_HTTP")
				unsetEnv(t, "SCHEDULE_SYNC_INTERVAL")
			},
			wantURL:           "https://api.example.com/v1",
			wantSync:          5 * time.Minute,
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
			if cfg.SyncInterval != tt.wantSync {
				t.Errorf("SyncInterval = %v, want %v", cfg.SyncInterval, tt.wantSync)
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
