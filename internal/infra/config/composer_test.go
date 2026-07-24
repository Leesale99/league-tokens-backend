package config

import (
	"os"
	"path/filepath"
	"testing"
)

func writeSecret(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0644); err != nil {
		t.Fatal(err)
	}
}

func setValidEnv(t *testing.T) {
	t.Helper()
	t.Setenv("PG_DATABASE", "league_tokens_test")
	t.Setenv("PG_USER", "testuser")
	t.Setenv("PG_HOST", "localhost")
	t.Setenv("PG_PORT", "5432")
	t.Setenv("PG_SSLMODE", "disable")
	t.Setenv("PG_MAX_CONNS", "10")
	t.Setenv("HTTP_LISTEN_ADDR", ":9090")
	t.Setenv("HTTP_TRUSTED_PROXIES", "10.0.0.1,10.0.0.2")
	t.Setenv("OTLP_ENDPOINT", "")
	t.Setenv("SERVICE_NAME", "league-tokens-test")
	t.Setenv("LOG_LEVEL", "debug")
	t.Setenv("SESSION_TTL", "1h")
	t.Setenv("SCHEDULE_PROVIDER_URL", "https://api.example.com/v1")
	t.Setenv("SCHEDULE_SYNC_INTERVAL", "10m")
	t.Setenv("FEED_PROVIDER_URL", "https://feed.example.com/v2")
	t.Setenv("FEED_POLL_INTERVAL", "2m")
}

func createSecrets(t *testing.T, dir string) {
	t.Helper()
	writeSecret(t, dir, "pg_password", "secret-pw")
	writeSecret(t, dir, "otlp_token", "otlp-token-val")
	writeSecret(t, dir, "jwt_signing_key", "ed25519-private-key-pem")
	writeSecret(t, dir, "provider_api_key", "provider-key-123")
}

func TestLoad_Valid(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	setValidEnv(t)
	createSecrets(t, secretsDir)

	cfg, err := Load()
	if err != nil {
		t.Fatalf("Load() returned error: %v", err)
	}

	if cfg.Postgres == nil {
		t.Fatal("Postgres config is nil")
	}
	if cfg.Postgres.Database != "league_tokens_test" {
		t.Errorf("Postgres.Database = %q, want %q", cfg.Postgres.Database, "league_tokens_test")
	}
	dsn := cfg.Postgres.DSN()
	if dsn == "" {
		t.Error("Postgres DSN is empty")
	}

	if cfg.HTTP == nil {
		t.Fatal("HTTP config is nil")
	}
	if cfg.HTTP.ListenAddr != ":9090" {
		t.Errorf("HTTP.ListenAddr = %q, want %q", cfg.HTTP.ListenAddr, ":9090")
	}
	if len(cfg.HTTP.TrustedProxies) != 2 {
		t.Errorf("HTTP.TrustedProxies length = %d, want 2", len(cfg.HTTP.TrustedProxies))
	}

	if cfg.Telemetry == nil {
		t.Fatal("Telemetry config is nil")
	}
	if cfg.Telemetry.ServiceName != "league-tokens-test" {
		t.Errorf("Telemetry.ServiceName = %q, want %q", cfg.Telemetry.ServiceName, "league-tokens-test")
	}
	if cfg.Telemetry.LogLevelSlog().String() != "DEBUG" {
		t.Errorf("LogLevelSlog = %q, want DEBUG", cfg.Telemetry.LogLevelSlog())
	}

	if cfg.Identity == nil {
		t.Fatal("Identity config is nil")
	}
	if cfg.Identity.JWTSigningKeyED25519 != "ed25519-private-key-pem" {
		t.Errorf("Identity.JWTSigningKeyED25519 = %q, want %q", cfg.Identity.JWTSigningKeyED25519, "ed25519-private-key-pem")
	}

	if cfg.Game == nil {
		t.Fatal("Game config is nil")
	}
	if cfg.Ledger == nil {
		t.Fatal("Ledger config is nil")
	}

	if cfg.Schedule == nil {
		t.Fatal("Schedule config is nil")
	}
	if cfg.Schedule.ProviderURL != "https://api.example.com/v1" {
		t.Errorf("Schedule.ProviderURL = %q, want %q", cfg.Schedule.ProviderURL, "https://api.example.com/v1")
	}
	if cfg.Schedule.ProviderAPIKey != "provider-key-123" {
		t.Errorf("Schedule.ProviderAPIKey = %q, want %q", cfg.Schedule.ProviderAPIKey, "provider-key-123")
	}
	if cfg.Schedule.SyncInterval.String() != "10m0s" {
		t.Errorf("Schedule.SyncInterval = %q, want %q", cfg.Schedule.SyncInterval, "10m0s")
	}

	if cfg.Feed == nil {
		t.Fatal("Feed config is nil")
	}
	if cfg.Feed.ProviderURL != "https://feed.example.com/v2" {
		t.Errorf("Feed.ProviderURL = %q, want %q", cfg.Feed.ProviderURL, "https://feed.example.com/v2")
	}
	if cfg.Feed.ProviderAPIKey != "provider-key-123" {
		t.Errorf("Feed.ProviderAPIKey = %q, want %q", cfg.Feed.ProviderAPIKey, "provider-key-123")
	}
}

func TestLoad_MissingPostgresDatabase(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	setValidEnv(t)
	// Unset required PG_DATABASE so env.Parse rejects it
	origPGDB, pgDBWasSet := os.LookupEnv("PG_DATABASE")
	os.Unsetenv("PG_DATABASE")
	t.Cleanup(func() {
		if pgDBWasSet {
			os.Setenv("PG_DATABASE", origPGDB)
		}
	})

	createSecrets(t, secretsDir)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error, got nil")
	}
}

func TestLoad_MissingScheduleProviderURL(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	setValidEnv(t)
	t.Setenv("SCHEDULE_PROVIDER_URL", "")
	createSecrets(t, secretsDir)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error, got nil")
	}
}

func TestLoad_MissingSecrets(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	setValidEnv(t)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error when secrets are missing, got nil")
	}
}

func TestLoad_InvalidLogLevel(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	setValidEnv(t)
	t.Setenv("LOG_LEVEL", "invalid")
	createSecrets(t, secretsDir)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for invalid LOG_LEVEL, got nil")
	}
}

func TestLoad_InvalidHTTPAddr(t *testing.T) {
	origDir := secretsDir
	secretsDir = t.TempDir()
	defer func() { secretsDir = origDir }()

	setValidEnv(t)
	t.Setenv("HTTP_LISTEN_ADDR", "not-a-valid-host-port")
	createSecrets(t, secretsDir)

	_, err := Load()
	if err == nil {
		t.Fatal("Load() expected error for invalid HTTP_LISTEN_ADDR, got nil")
	}
}

func TestPostgresDSN(t *testing.T) {
	cfg := &PostgresConfig{
		Database: "testdb",
		User:     "testuser",
		Host:     "localhost",
		Port:     5432,
		SSLMode:  "require",
		MaxConns: 10,
		password: "secret",
	}
	dsn := cfg.DSN()
	want := "postgres://testuser:secret@localhost:5432/testdb?sslmode=require"
	if dsn != want {
		t.Errorf("DSN = %q, want %q", dsn, want)
	}
}

func TestTelemetryLogLevelSlog(t *testing.T) {
	tests := []struct {
		level string
		want  string
	}{
		{"debug", "DEBUG"},
		{"info", "INFO"},
		{"warn", "WARN"},
		{"error", "ERROR"},
		{"INFO", "INFO"},
		{"unknown", "INFO"},
		{"", "INFO"},
	}
	for _, tt := range tests {
		cfg := &TelemetryConfig{LogLevel: tt.level}
		got := cfg.LogLevelSlog().String()
		if got != tt.want {
			t.Errorf("LogLevelSlog(%q) = %q, want %q", tt.level, got, tt.want)
		}
	}
}
