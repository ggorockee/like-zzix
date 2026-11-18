// Command api serves composition presets and collects anonymous app metrics
// for the 라익찍스 (like-zzix) app.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/ggorockee/like-zzix/server/internal/config"
	"github.com/ggorockee/like-zzix/server/internal/httpapi"
	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/telemetry"
)

// Set at build time: -ldflags "-X main.version=... -X main.commit=...".
var (
	version = "dev"
	commit  = "none"
)

func main() {
	cfg, err := config.Load()
	log := newLogger(cfg.LogLevel)
	slog.SetDefault(log)
	if err == nil {
		err = run(cfg, log)
	}
	if err != nil {
		log.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func newLogger(level string) *slog.Logger {
	var l slog.Level
	if err := l.UnmarshalText([]byte(level)); err != nil {
		l = slog.LevelInfo
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: l})).
		With("service", "like-zzix-server", "version", version)
}

func run(cfg config.Config, log *slog.Logger) error {
	catalog, err := presets.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	metrics := telemetry.New(version, commit)
	api := httpapi.New(catalog, httpapi.Options{Metrics: metrics, Log: log})
	metricsApp := httpapi.NewMetricsApp(metrics)

	errCh := make(chan error, 2)
	go func() { errCh <- api.Listen(":" + cfg.Port) }()
	go func() { errCh <- metricsApp.Listen(":" + cfg.MetricsPort) }()
	log.Info("listening", "port", cfg.Port, "metrics_port", cfg.MetricsPort, "presets", catalog.Len())

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("shutting down")
		_ = metricsApp.ShutdownWithTimeout(5 * time.Second)
		return api.ShutdownWithTimeout(10 * time.Second)
	}
}
