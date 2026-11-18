// Package config loads settings from environment variables.
package config

import (
	"fmt"
	"os"
)

// Config is the server configuration.
type Config struct {
	Port        string // PORT, default 8080
	MetricsPort string // METRICS_PORT, default 9090; serves /metrics only
	LogLevel    string // LOG_LEVEL: debug, info (default), warn, error
}

// Load reads the configuration from the environment.
func Load() (Config, error) {
	c := Config{
		Port:        getenv("PORT", "8080"),
		MetricsPort: getenv("METRICS_PORT", "9090"),
		LogLevel:    getenv("LOG_LEVEL", "info"),
	}
	if c.MetricsPort == c.Port {
		return c, fmt.Errorf("METRICS_PORT must differ from PORT (%s)", c.Port)
	}
	return c, nil
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
