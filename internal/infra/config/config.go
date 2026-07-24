package config

import (
	"fmt"
	"log/slog"
	"net"
	"strings"

	"github.com/caarlos0/env/v11"
)

type PostgresConfig struct {
	Database string `env:"PG_DATABASE,required"`
	User     string `env:"PG_USER,required"`
	Host     string `env:"PG_HOST" envDefault:"localhost"`
	Port     int    `env:"PG_PORT" envDefault:"5432"`
	SSLMode  string `env:"PG_SSLMODE" envDefault:"disable"`
	MaxConns int    `env:"PG_MAX_CONNS" envDefault:"25"`

	password string
}

func (c *PostgresConfig) DSN() string {
	ssl := c.SSLMode
	if ssl == "" {
		ssl = "disable"
	}
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=%s",
		c.User, c.password, c.Host, c.Port, c.Database, ssl)
}

func (c *PostgresConfig) Validate() error {
	var errs []string
	if c.Database == "" {
		errs = append(errs, "PG_DATABASE must not be empty")
	}
	if c.User == "" {
		errs = append(errs, "PG_USER must not be empty")
	}
	if c.Host == "" {
		errs = append(errs, "PG_HOST must not be empty")
	}
	if c.Port < 1 || c.Port > 65535 {
		errs = append(errs, "PG_PORT must be between 1 and 65535")
	}
	if c.MaxConns < 1 {
		errs = append(errs, "PG_MAX_CONNS must be at least 1")
	}
	if c.password == "" {
		errs = append(errs, "pg_password secret is required")
	}
	if len(errs) > 0 {
		return fmt.Errorf("postgres config: %s", strings.Join(errs, "; "))
	}
	return nil
}

func parsePostgresConfig() (*PostgresConfig, error) {
	var cfg PostgresConfig
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse postgres config: %w", err)
	}
	return &cfg, nil
}

type HTTPConfig struct {
	ListenAddr       string   `env:"HTTP_LISTEN_ADDR" envDefault:":8080"`
	TrustedProxies   []string `env:"HTTP_TRUSTED_PROXIES" envSeparator:","`
}

func (c *HTTPConfig) Validate() error {
	var errs []string
	if c.ListenAddr == "" {
		errs = append(errs, "HTTP_LISTEN_ADDR must not be empty")
	} else if _, _, err := net.SplitHostPort(c.ListenAddr); err != nil {
		errs = append(errs, "HTTP_LISTEN_ADDR must be host:port")
	}
	for _, p := range c.TrustedProxies {
		if net.ParseIP(p) == nil {
			errs = append(errs, fmt.Sprintf("HTTP_TRUSTED_PROXIES contains invalid IP: %s", p))
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("http config: %s", strings.Join(errs, "; "))
	}
	return nil
}

func parseHTTPConfig() (*HTTPConfig, error) {
	var cfg HTTPConfig
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse http config: %w", err)
	}
	return &cfg, nil
}

type TelemetryConfig struct {
	OTLPEndpoint string `env:"OTLP_ENDPOINT" envDefault:""`
	OTLPToken    string
	ServiceName  string `env:"SERVICE_NAME" envDefault:"league-tokens-backend"`
	LogLevel     string `env:"LOG_LEVEL" envDefault:"info"`
}

func (c *TelemetryConfig) LogLevelSlog() slog.Level {
	switch strings.ToLower(c.LogLevel) {
	case "debug":
		return slog.LevelDebug
	case "warn":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

func (c *TelemetryConfig) Validate() error {
	var errs []string
	switch strings.ToLower(c.LogLevel) {
	case "debug", "info", "warn", "error":
	default:
		errs = append(errs, "LOG_LEVEL must be one of: debug, info, warn, error")
	}
	if c.OTLPEndpoint != "" && c.OTLPToken == "" {
		errs = append(errs, "otlp_token secret is required when OTLP_ENDPOINT is set")
	}
	if c.ServiceName == "" {
		errs = append(errs, "SERVICE_NAME must not be empty")
	}
	if len(errs) > 0 {
		return fmt.Errorf("telemetry config: %s", strings.Join(errs, "; "))
	}
	return nil
}

func parseTelemetryConfig() (*TelemetryConfig, error) {
	var cfg TelemetryConfig
	if err := env.Parse(&cfg); err != nil {
		return nil, fmt.Errorf("parse telemetry config: %w", err)
	}
	return &cfg, nil
}
