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
				SessionTTL:           24 * time.Hour,
				JWTSigningKeyED25519: "ed25519-private-key-pem",
			},
			wantErr: false,
		},
		{
			name: "zero session TTL",
			cfg: Config{
				SessionTTL:           0,
				JWTSigningKeyED25519: "ed25519-private-key-pem",
			},
			wantErr: true,
		},
		{
			name: "negative session TTL",
			cfg: Config{
				SessionTTL:           -1 * time.Hour,
				JWTSigningKeyED25519: "ed25519-private-key-pem",
			},
			wantErr: true,
		},
		{
			name: "missing signing key",
			cfg: Config{
				SessionTTL:           24 * time.Hour,
				JWTSigningKeyED25519: "",
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
			os.Setenv(key, old)
		} else {
			os.Unsetenv(key)
		}
	})
}

func TestParseConfig(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(t *testing.T)
		wantTTL   time.Duration
		wantErr   bool
		errSubstr string
	}{
		{
			name: "session TTL default",
			setup: func(t *testing.T) {
				unsetEnv(t, "SESSION_TTL")
			},
			wantTTL: 24 * time.Hour,
		},
		{
			name: "custom session TTL",
			setup: func(t *testing.T) {
				t.Setenv("SESSION_TTL", "1h")
			},
			wantTTL: time.Hour,
		},
		{
			name: "invalid session TTL",
			setup: func(t *testing.T) {
				t.Setenv("SESSION_TTL", "abc")
			},
			wantErr:   true,
			errSubstr: "parse identity config",
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
			if cfg.SessionTTL != tt.wantTTL {
				t.Errorf("SessionTTL = %v, want %v", cfg.SessionTTL, tt.wantTTL)
			}
			if cfg.JWTSigningKeyED25519 != "" {
				t.Errorf("JWTSigningKeyED25519 = %q, want empty (injected by infra/config.Load)", cfg.JWTSigningKeyED25519)
			}
		})
	}
}
