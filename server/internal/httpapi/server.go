// Package httpapi wires the public HTTP API and the separate /metrics app.
package httpapi

import (
	_ "embed"
	"log/slog"
	"strings"
	"time"

	"github.com/gofiber/adaptor/v2"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/prometheus/client_golang/prometheus/promhttp"

	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/telemetry"
)

// Options configures New.
type Options struct {
	Metrics *telemetry.Metrics
	Log     *slog.Logger
}

type eventsRequest struct {
	Events []struct {
		Name   string `json:"name"`
		Count  int    `json:"count"`
		Preset string `json:"preset"`
	} `json:"events"`
}

//go:embed privacy.html
var privacyHTML []byte

// New builds the public API.
func New(catalog *presets.Catalog, opt Options) *fiber.App {
	if opt.Metrics == nil {
		opt.Metrics = telemetry.New("dev", "none")
	}
	if opt.Log == nil {
		opt.Log = slog.Default()
	}
	m := opt.Metrics
	m.SetPresets(catalog.IDs())

	app := fiber.New(fiber.Config{
		AppName:               "like-zzix",
		DisableStartupMessage: true,
		BodyLimit:             16 * 1024, // the largest legitimate body is a small events batch
		// Fiber reuses buffers; Immutable keeps route/header strings safe to use
		// as Prometheus labels after the handler returns.
		Immutable: true,
		ErrorHandler: func(c *fiber.Ctx, err error) error {
			code := fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				code = e.Code
			}
			return c.Status(code).JSON(fiber.Map{"error": err.Error()})
		},
	})
	app.Use(recover.New())
	app.Use(observe(m, opt.Log))

	app.Get("/healthz", func(c *fiber.Ctx) error { return c.SendString("ok") })
	// Presets are embedded and validated at startup, so readiness only means "serving".
	app.Get("/readyz", func(c *fiber.Ctx) error { return c.SendString("ok") })

	v1 := app.Group("/v1")
	v1.Get("/presets", func(c *fiber.Ctx) error {
		c.Set(fiber.HeaderETag, catalog.ETag())
		c.Set(fiber.HeaderCacheControl, "public, max-age=300")
		if matchETag(c.Get(fiber.HeaderIfNoneMatch), catalog.ETag()) {
			return c.SendStatus(fiber.StatusNotModified)
		}
		c.Set(fiber.HeaderContentType, fiber.MIMEApplicationJSONCharsetUTF8)
		return c.Send(catalog.ListJSON())
	})
	v1.Get("/presets/:id", func(c *fiber.Ctx) error {
		body, ok := catalog.Get(c.Params("id"))
		if !ok {
			return fiber.NewError(fiber.StatusNotFound, "preset not found")
		}
		c.Set(fiber.HeaderCacheControl, "public, max-age=300")
		c.Set(fiber.HeaderContentType, fiber.MIMEApplicationJSONCharsetUTF8)
		return c.Send(body)
	})
	v1.Get("/categories", func(c *fiber.Ctx) error {
		c.Set(fiber.HeaderCacheControl, "public, max-age=300")
		return c.JSON(fiber.Map{"items": catalog.Categories()})
	})
	v1.Post("/events", func(c *fiber.Ctx) error {
		var req eventsRequest
		if err := c.BodyParser(&req); err != nil {
			m.EventRejected("malformed")
			return fiber.NewError(fiber.StatusBadRequest, "malformed body")
		}
		if len(req.Events) == 0 || len(req.Events) > telemetry.MaxEventsPerBatch {
			m.EventRejected("batch_size")
			return fiber.NewError(fiber.StatusBadRequest, "invalid batch size")
		}
		platform := c.Get("X-App-Platform")
		accepted := 0
		for _, e := range req.Events {
			switch {
			case !telemetry.AllowedEvents[e.Name]:
				m.EventRejected("unknown_event")
			case e.Count < 1 || e.Count > telemetry.MaxEventCount:
				m.EventRejected("invalid_count")
			default:
				m.AppEvent(e.Name, platform, e.Count)
				// Per-preset funnel only for known presets (bounded labels).
				if telemetry.PresetEvents[e.Name] && catalog.Has(e.Preset) {
					m.PresetEvent(e.Name, e.Preset, e.Count)
				}
				accepted++
			}
		}
		return c.Status(fiber.StatusAccepted).JSON(fiber.Map{"accepted": accepted})
	})

	app.Get("/privacy", func(c *fiber.Ctx) error {
		c.Set(fiber.HeaderContentType, fiber.MIMETextHTMLCharsetUTF8)
		c.Set(fiber.HeaderCacheControl, "public, max-age=3600")
		return c.Send(privacyHTML)
	})

	return app
}

// NewMetricsApp serves /metrics on its own port (not routed by the VirtualService).
func NewMetricsApp(m *telemetry.Metrics) *fiber.App {
	app := fiber.New(fiber.Config{AppName: "like-zzix-metrics", DisableStartupMessage: true})
	app.Get("/metrics", adaptor.HTTPHandler(promhttp.HandlerFor(m.Registry, promhttp.HandlerOpts{})))
	return app
}

func matchETag(header, etag string) bool {
	for _, v := range strings.Split(header, ",") {
		v = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(v), "W/"))
		if v == etag || v == "*" {
			return true
		}
	}
	return false
}

func observe(m *telemetry.Metrics, log *slog.Logger) fiber.Handler {
	return func(c *fiber.Ctx) error {
		start := time.Now()
		m.InFlight(1)
		defer m.InFlight(-1)

		err := c.Next()

		status := c.Response().StatusCode()
		if err != nil {
			status = fiber.StatusInternalServerError
			if e, ok := err.(*fiber.Error); ok {
				status = e.Code
			}
		}

		route := c.Route().Path
		if route == "" || route == "/" && c.Path() != "/" {
			route = "unmatched"
		}
		elapsed := time.Since(start)
		m.HTTP(c.Method(), route, status, elapsed.Seconds())

		if strings.HasPrefix(route, "/v1/") {
			m.AppRequest(c.Get("X-App-Platform"), c.Get("X-App-Version"))
		}
		if route != "/healthz" && route != "/readyz" {
			level := slog.LevelInfo
			if status >= 500 {
				level = slog.LevelError
			} else if status >= 400 {
				level = slog.LevelWarn
			}
			log.Log(c.UserContext(), level, "http request",
				"method", c.Method(), "route", route, "status", status,
				"duration_ms", elapsed.Milliseconds(),
				"platform", telemetry.NormalizePlatform(c.Get("X-App-Platform")),
				"app_version", telemetry.NormalizeVersion(c.Get("X-App-Version")))
		}
		return err
	}
}
