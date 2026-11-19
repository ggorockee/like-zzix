// Command api serves composition presets, collects anonymous app metrics and
// hosts the admin API for the 라익찍스 (like-zzix) app.
package main

import (
	"context"
	"encoding/json"
	"log/slog"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/ggorockee/like-zzix/server/internal/admin"
	"github.com/ggorockee/like-zzix/server/internal/catalog"
	"github.com/ggorockee/like-zzix/server/internal/config"
	"github.com/ggorockee/like-zzix/server/internal/httpapi"
	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/store"
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
	embedded, err := presets.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	metrics := telemetry.New(version, commit)

	// 저장소: 운영은 Cloud SQL, 로컬 개발은 메모리, 둘 다 없으면 내장 프리셋만 제공
	var st store.Store
	mode := "static"
	switch {
	case cfg.HasDatabase():
		pg, err := store.OpenPostgres(ctx, cfg.DatabaseURL())
		if err != nil {
			// DB 장애로 앱 API까지 멈추지 않도록 내장 프리셋으로 계속 제공하고 알림(db_up=0)으로 감지
			log.Error("database unavailable at startup; serving embedded presets", "err", err)
			metrics.DBUp(false)
			metrics.DBError("connect")
		} else {
			defer pg.Close()
			if applied, err := pg.Migrate(ctx); err != nil {
				return err
			} else if len(applied) > 0 {
				log.Info("migrations applied", "files", applied)
			}
			st, mode = pg, "postgres"
		}
	case cfg.Local():
		st, mode = store.NewMemory(), "memory"
	}

	holder := catalog.Static(embedded, metrics)
	if st != nil {
		if err := seed(ctx, st, log); err != nil {
			return err
		}
		holder = catalog.FromStore(st, embedded, metrics, log)
		if err := holder.Refresh(ctx); err != nil {
			log.Error("initial catalog load failed; serving embedded presets", "err", err)
		}
		go holder.Run(ctx, 30*time.Second)
	}

	opts := httpapi.Options{Metrics: metrics, Log: log, Store: st}
	if cfg.AdminEnabled() && st != nil {
		adminOpts, err := newAdmin(ctx, cfg, st)
		if err != nil {
			return err
		}
		opts.Admin = adminOpts
		go purgeSessions(ctx, st, log)
	} else {
		log.Warn("admin API disabled (needs database, ADMIN_EMAILS and GOOGLE_CLIENT_ID)")
	}

	api := httpapi.New(holder, opts)
	metricsApp := httpapi.NewMetricsApp(metrics)

	errCh := make(chan error, 2)
	go func() { errCh <- api.Listen(":" + cfg.Port) }()
	go func() { errCh <- metricsApp.Listen(":" + cfg.MetricsPort) }()
	log.Info("listening", "port", cfg.Port, "metrics_port", cfg.MetricsPort,
		"store", mode, "admin", opts.Admin != nil, "presets", holder.Current().Len())

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		log.Info("shutting down")
		_ = metricsApp.ShutdownWithTimeout(5 * time.Second)
		return api.ShutdownWithTimeout(10 * time.Second)
	}
}

// seed copies the bundled presets into an empty store as published presets.
func seed(ctx context.Context, st store.Store, log *slog.Logger) error {
	_, items, err := presets.Embedded()
	if err != nil {
		return err
	}
	orders := make([]int, len(items))
	for i, item := range items {
		var head struct {
			SortOrder int `json:"sort_order"`
		}
		_ = json.Unmarshal(item, &head)
		orders[i] = head.SortOrder
	}
	n, err := st.SeedIfEmpty(ctx, items, orders, "seed")
	if err != nil {
		return err
	}
	if n > 0 {
		log.Info("seeded presets from bundled file", "count", n)
	}
	return nil
}

func newAdmin(ctx context.Context, cfg config.Config, st store.Store) (*httpapi.AdminOptions, error) {
	var verifier admin.Verifier = rejectAll{}
	if cfg.GoogleClientID != "" {
		v, err := admin.NewGoogleVerifier(ctx, cfg.GoogleClientID)
		if err != nil {
			return nil, err
		}
		verifier = v
	}
	password, err := admin.NewPasswordLogin(cfg.AdminLoginID, cfg.AdminPassHash)
	if err != nil {
		return nil, err
	}
	allow := admin.ParseAllowlist(cfg.AdminEmails)
	if password != nil {
		allow[strings.ToLower(password.ID)] = true
	}
	if cfg.AdminDevEmail != "" {
		allow[cfg.AdminDevEmail] = true
	}
	return &httpapi.AdminOptions{
		Store:          st,
		Verifier:       verifier,
		Allowlist:      allow,
		Sessions:       &admin.Sessions{Store: st, TTL: 12 * time.Hour},
		Origin:         cfg.AdminOrigin,
		GoogleClientID: cfg.GoogleClientID,
		CookieSecure:   !cfg.Local(),
		Password:       password,
		DevEmail:       cfg.AdminDevEmail,
	}, nil
}

type rejectAll struct{}

func (rejectAll) Verify(context.Context, string) (string, error) { return "", admin.ErrInvalidToken }

func purgeSessions(ctx context.Context, st store.Store, log *slog.Logger) {
	t := time.NewTicker(time.Hour)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if n, err := st.DeleteExpiredSessions(ctx, time.Now()); err != nil {
				log.Warn("session purge failed", "err", err)
			} else if n > 0 {
				log.Info("expired admin sessions purged", "count", n)
			}
		}
	}
}
