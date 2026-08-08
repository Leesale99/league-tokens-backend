package feed

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
