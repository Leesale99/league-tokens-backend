package application

import (
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
