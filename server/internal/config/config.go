// Package config loads settings from environment variables.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
)

// Config is the server configuration.
type Config struct {
	Port        string // PORT, default 8080
	MetricsPort string // METRICS_PORT, default 9090; serves /metrics only
	LogLevel    string // LOG_LEVEL: debug, info (default), warn, error
	AppEnv      string // APP_ENV: production (default) or local

	// Database (POSTGRES_* from the prod-like-zzix-db-credentials secret).
	// Empty host = static mode: embedded presets, admin API disabled (or in-memory when APP_ENV=local).
	PostgresHost     string
	PostgresPort     string
	PostgresUser     string
	PostgresPassword string
	PostgresDB       string
	PostgresSSLMode  string

	// Admin console.
	AdminEmails    string // ADMIN_EMAILS: comma-separated superuser allowlist
	GoogleClientID string // GOOGLE_CLIENT_ID: OAuth web client used by the console login
	AdminOrigin    string // ADMIN_ORIGIN: console origin for CORS
	AdminLoginID   string // ADMIN_LOGIN_ID: break-glass ID/PW account (with ADMIN_PASSWORD_HASH)
	AdminPassHash  string // ADMIN_PASSWORD_HASH: bcrypt hash of that account's password
	AdminDevEmail  string // ADMIN_DEV_EMAIL: local-only password-less login (APP_ENV=local)
}

// Load reads the configuration from the environment.
func Load() (Config, error) {
	c := Config{
		Port:             getenv("PORT", "8080"),
		MetricsPort:      getenv("METRICS_PORT", "9090"),
		LogLevel:         getenv("LOG_LEVEL", "info"),
		AppEnv:           getenv("APP_ENV", "production"),
		PostgresHost:     os.Getenv("POSTGRES_HOST"),
		PostgresPort:     getenv("POSTGRES_PORT", "5432"),
		PostgresUser:     os.Getenv("POSTGRES_USER"),
		PostgresPassword: os.Getenv("POSTGRES_PASSWORD"),
		PostgresDB:       os.Getenv("POSTGRES_DB"),
		PostgresSSLMode:  getenv("POSTGRES_SSLMODE", "disable"),
		AdminEmails:      os.Getenv("ADMIN_EMAILS"),
		GoogleClientID:   os.Getenv("GOOGLE_CLIENT_ID"),
		AdminOrigin:      os.Getenv("ADMIN_ORIGIN"),
		AdminLoginID:     os.Getenv("ADMIN_LOGIN_ID"),
		AdminPassHash:    os.Getenv("ADMIN_PASSWORD_HASH"),
		AdminDevEmail:    os.Getenv("ADMIN_DEV_EMAIL"),
	}
	if c.MetricsPort == c.Port {
		return c, fmt.Errorf("METRICS_PORT must differ from PORT (%s)", c.Port)
	}
	if c.AdminDevEmail != "" && !c.Local() {
		return c, errors.New("ADMIN_DEV_EMAIL is only allowed with APP_ENV=local")
	}
	return c, nil
}

// Local reports whether this is a developer machine.
func (c Config) Local() bool { return c.AppEnv == "local" }

// HasDatabase reports whether Postgres is configured.
func (c Config) HasDatabase() bool { return c.PostgresHost != "" }

// DatabaseURL builds the pgx connection string.
func (c Config) DatabaseURL() string {
	u := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(c.PostgresUser, c.PostgresPassword),
		Host:     c.PostgresHost + ":" + c.PostgresPort,
		Path:     "/" + c.PostgresDB,
		RawQuery: "sslmode=" + url.QueryEscape(c.PostgresSSLMode),
	}
	return u.String()
}

// AdminEnabled reports whether the admin API can run (needs storage and a login method).
func (c Config) AdminEnabled() bool {
	hasStore := c.HasDatabase() || c.Local()
	hasPassword := c.AdminLoginID != "" && c.AdminPassHash != ""
	hasLogin := c.GoogleClientID != "" || c.AdminDevEmail != "" || hasPassword
	return hasStore && hasLogin && (c.AdminEmails != "" || hasPassword)
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
