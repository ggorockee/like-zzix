package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"strings"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/limiter"

	"github.com/ggorockee/like-zzix/server/internal/admin"
	"github.com/ggorockee/like-zzix/server/internal/catalog"
	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/store"
	"github.com/ggorockee/like-zzix/server/internal/telemetry"
)

// AdminOptions configures /admin/v1.
type AdminOptions struct {
	Store     store.Store
	Verifier  admin.Verifier
	Allowlist admin.Allowlist
	Sessions  *admin.Sessions
	// Origin is the admin console origin allowed by CORS (e.g. https://like-zzix-admin.woohalabs.com).
	Origin string
	// GoogleClientID is handed to the console's login button.
	GoogleClientID string
	// CookieSecure must be true in production (HTTPS).
	CookieSecure bool
	// Password enables POST /admin/v1/auth/password (break-glass ID/PW account); nil disables it.
	Password *admin.PasswordLogin
	// DevEmail enables POST /admin/v1/auth/dev for local development only. Never set in production.
	DevEmail string
	// LoginLimit is login attempts per minute per IP (default 5).
	LoginLimit int
}

const (
	sessionCookie = "lzx_admin"
	maxImageBytes = 1536 * 1024
)

type presetRequest struct {
	Doc       json.RawMessage `json:"doc"`
	SortOrder int             `json:"sort_order"`
}

func mountAdmin(app *fiber.App, holder *catalog.Holder, m *telemetry.Metrics, log *slog.Logger, opt *AdminOptions) {
	if opt.LoginLimit == 0 {
		opt.LoginLimit = 5
	}
	g := app.Group("/admin/v1", cors.New(cors.Config{
		AllowOrigins:     opt.Origin,
		AllowCredentials: true,
		AllowMethods:     "GET,POST,PUT,PATCH,DELETE",
		AllowHeaders:     "Content-Type",
		MaxAge:           600,
	}))

	// 로그인 화면이 쓰는 공개 설정
	g.Get("/config", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"google_client_id": opt.GoogleClientID,
			"categories":       presets.CategoryIDs(),
			"dev_login":        opt.DevEmail != "",
			"password_login":   opt.Password != nil,
		})
	})

	loginLimiter := limiter.New(limiter.Config{
		Max:        opt.LoginLimit,
		Expiration: time.Minute,
		LimitReached: func(c *fiber.Ctx) error {
			m.AdminLogin("rate_limited")
			return fiber.NewError(fiber.StatusTooManyRequests, "too many login attempts")
		},
	})
	g.Post("/auth/google", loginLimiter, func(c *fiber.Ctx) error {
		var req struct {
			Credential string `json:"credential"`
		}
		if err := c.BodyParser(&req); err != nil || req.Credential == "" {
			m.AdminLogin("invalid_token")
			return fiber.NewError(fiber.StatusBadRequest, "credential is required")
		}
		email, err := opt.Verifier.Verify(c.UserContext(), req.Credential)
		if err != nil {
			m.AdminLogin("invalid_token")
			log.Warn("admin login rejected", "reason", "invalid_token", "err", err)
			return fiber.NewError(fiber.StatusUnauthorized, "invalid google credential")
		}
		return startSession(c, m, log, opt, email)
	})
	if opt.Password != nil {
		g.Post("/auth/password", loginLimiter, func(c *fiber.Ctx) error {
			var req struct {
				ID       string `json:"id"`
				Password string `json:"password"`
			}
			if err := c.BodyParser(&req); err != nil || req.ID == "" || req.Password == "" {
				m.AdminLogin("invalid_password")
				return fiber.NewError(fiber.StatusBadRequest, "id and password are required")
			}
			if !opt.Password.Check(strings.TrimSpace(req.ID), req.Password) {
				m.AdminLogin("invalid_password")
				log.Warn("admin login rejected", "reason", "invalid_password")
				return fiber.NewError(fiber.StatusUnauthorized, "invalid id or password")
			}
			return startSession(c, m, log, opt, opt.Password.ID)
		})
	}
	if opt.DevEmail != "" {
		g.Post("/auth/dev", func(c *fiber.Ctx) error {
			return startSession(c, m, log, opt, opt.DevEmail)
		})
	}

	auth := requireSession(opt)
	g.Post("/auth/logout", auth, func(c *fiber.Ctx) error {
		_ = opt.Sessions.Delete(c.UserContext(), c.Cookies(sessionCookie))
		c.Cookie(sessionCookieFor(opt, "", time.Unix(0, 0)))
		return c.SendStatus(fiber.StatusNoContent)
	})
	g.Get("/me", auth, func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"email": c.Locals("email")})
	})

	g.Get("/presets", auth, func(c *fiber.Ctx) error {
		list, err := opt.Store.ListPresets(c.UserContext(), false)
		if err != nil {
			m.DBError("list_presets")
			return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
		}
		if list == nil {
			list = []store.Preset{}
		}
		return c.JSON(fiber.Map{"items": list})
	})
	g.Get("/presets/:id", auth, func(c *fiber.Ctx) error {
		p, err := opt.Store.GetPreset(c.UserContext(), c.Params("id"))
		if err != nil {
			return storeErr(m, "get_preset", err)
		}
		return c.JSON(p)
	})
	g.Post("/presets", auth, func(c *fiber.Ctx) error {
		req, p, err := parsePreset(c)
		if err != nil {
			return err
		}
		err = opt.Store.CreatePreset(c.UserContext(), p.ID, req.Doc, req.SortOrder, email(c))
		if errors.Is(err, store.ErrExists) {
			return fiber.NewError(fiber.StatusConflict, "preset id already exists")
		}
		if err != nil {
			return storeErr(m, "create_preset", err)
		}
		return changed(c, holder, m, log, "create", p.ID, fiber.StatusCreated)
	})
	g.Put("/presets/:id", auth, func(c *fiber.Ctx) error {
		req, p, err := parsePreset(c)
		if err != nil {
			return err
		}
		if p.ID != c.Params("id") {
			return fiber.NewError(fiber.StatusBadRequest, "doc.id must match the path (ids cannot be renamed)")
		}
		if err := opt.Store.UpdatePreset(c.UserContext(), p.ID, req.Doc, req.SortOrder, email(c)); err != nil {
			return storeErr(m, "update_preset", err)
		}
		return changed(c, holder, m, log, "update", p.ID, fiber.StatusOK)
	})
	g.Delete("/presets/:id", auth, func(c *fiber.Ctx) error {
		if err := opt.Store.DeletePreset(c.UserContext(), c.Params("id")); err != nil {
			return storeErr(m, "delete_preset", err)
		}
		return changed(c, holder, m, log, "delete", c.Params("id"), fiber.StatusOK)
	})
	g.Patch("/presets/:id/status", auth, func(c *fiber.Ctx) error {
		var req struct {
			Status string `json:"status"`
		}
		if err := c.BodyParser(&req); err != nil ||
			(req.Status != store.StatusDraft && req.Status != store.StatusPublished) {
			return fiber.NewError(fiber.StatusBadRequest, "status must be draft or published")
		}
		if err := opt.Store.SetStatus(c.UserContext(), c.Params("id"), req.Status, email(c)); err != nil {
			return storeErr(m, "set_status", err)
		}
		action := "publish"
		if req.Status == store.StatusDraft {
			action = "unpublish"
		}
		return changed(c, holder, m, log, action, c.Params("id"), fiber.StatusOK)
	})
	g.Put("/presets/:id/image", auth, func(c *fiber.Ctx) error {
		data := c.Body()
		if len(data) == 0 || len(data) > maxImageBytes {
			return fiber.NewError(fiber.StatusRequestEntityTooLarge, "image must be 1 byte to 1.5MB")
		}
		ctype := sniffImage(data)
		if ctype == "" {
			return fiber.NewError(fiber.StatusUnsupportedMediaType, "image must be JPEG, PNG or WebP")
		}
		if _, err := opt.Store.PutImage(c.UserContext(), c.Params("id"), data, ctype, email(c)); err != nil {
			return storeErr(m, "put_image", err)
		}
		return changed(c, holder, m, log, "image", c.Params("id"), fiber.StatusOK)
	})
	// 초안 미리보기용 (공개 경로는 공개된 프리셋 사진만 제공)
	g.Get("/presets/:id/image", auth, func(c *fiber.Ctx) error {
		return sendImage(c, opt.Store, m, c.Params("id"))
	})
}

func startSession(c *fiber.Ctx, m *telemetry.Metrics, log *slog.Logger, opt *AdminOptions, email string) error {
	// 대소문자·공백이 달라도 같은 계정으로 취급 (세션·감사 로그·허용 목록 일치)
	email = strings.ToLower(strings.TrimSpace(email))
	if !opt.Allowlist.Allowed(email) {
		m.AdminLogin("not_allowed")
		log.Warn("admin login rejected", "reason", "not_allowed", "email", email)
		return fiber.NewError(fiber.StatusForbidden, "this account is not an admin")
	}
	token, expires, err := opt.Sessions.Create(c.UserContext(), email)
	if err != nil {
		m.DBError("create_session")
		return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
	}
	m.AdminLogin("success")
	log.Info("admin login", "email", email)
	c.Cookie(sessionCookieFor(opt, token, expires))
	return c.JSON(fiber.Map{"email": email, "expires_at": expires})
}

func sessionCookieFor(opt *AdminOptions, token string, expires time.Time) *fiber.Cookie {
	return &fiber.Cookie{
		Name:     sessionCookie,
		Value:    token,
		Path:     "/admin",
		Expires:  expires,
		HTTPOnly: true,
		Secure:   opt.CookieSecure,
		// 콘솔(like-zzix-admin.woohalabs.com)과 API(like-zzix.woohalabs.com)는 같은 사이트라 Strict로 충분
		SameSite: fiber.CookieSameSiteStrictMode,
	}
}

func requireSession(opt *AdminOptions) fiber.Handler {
	return func(c *fiber.Ctx) error {
		email, err := opt.Sessions.Lookup(c.UserContext(), c.Cookies(sessionCookie))
		if errors.Is(err, store.ErrNotFound) {
			return fiber.NewError(fiber.StatusUnauthorized, "login required")
		}
		if err != nil {
			return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
		}
		// 세션이 남아 있어도 허용 목록에서 빠진 계정은 차단
		if !opt.Allowlist.Allowed(email) {
			return fiber.NewError(fiber.StatusForbidden, "this account is not an admin")
		}
		c.Locals("email", email)
		return c.Next()
	}
}

func email(c *fiber.Ctx) string { s, _ := c.Locals("email").(string); return s }

func parsePreset(c *fiber.Ctx) (presetRequest, presets.Preset, error) {
	var req presetRequest
	if err := json.Unmarshal(c.Body(), &req); err != nil || len(req.Doc) == 0 {
		return req, presets.Preset{}, fiber.NewError(fiber.StatusBadRequest, "body must be {\"doc\": {...}, \"sort_order\": n}")
	}
	// 공개 사진 주소는 서버가 붙이므로 저장하지 않는다.
	var m map[string]json.RawMessage
	if err := json.Unmarshal(req.Doc, &m); err == nil {
		if _, ok := m["reference_url"]; ok {
			delete(m, "reference_url")
			req.Doc, _ = json.Marshal(m)
		}
	}
	p, err := presets.Validate(req.Doc)
	if err != nil {
		return req, p, fiber.NewError(fiber.StatusUnprocessableEntity, "invalid preset: "+err.Error())
	}
	return req, p, nil
}

func storeErr(m *telemetry.Metrics, op string, err error) error {
	if errors.Is(err, store.ErrNotFound) {
		return fiber.NewError(fiber.StatusNotFound, "preset not found")
	}
	m.DBError(op)
	return fiber.NewError(fiber.StatusServiceUnavailable, "database unavailable")
}

// changed records the change and reloads the public catalog right away.
func changed(c *fiber.Ctx, holder *catalog.Holder, m *telemetry.Metrics, log *slog.Logger, action, id string, status int) error {
	m.AdminChange(action)
	log.Info("admin change", "action", action, "preset", id, "email", email(c))
	ctx, cancel := context.WithTimeout(c.UserContext(), 5*time.Second)
	defer cancel()
	if err := holder.Refresh(ctx); err != nil {
		log.Warn("catalog refresh after admin change failed", "err", err)
	}
	return c.Status(status).JSON(fiber.Map{"id": id, "action": action})
}

func sniffImage(b []byte) string {
	switch {
	case bytes.HasPrefix(b, []byte{0xFF, 0xD8, 0xFF}):
		return "image/jpeg"
	case bytes.HasPrefix(b, []byte("\x89PNG\r\n\x1a\n")):
		return "image/png"
	case len(b) >= 12 && string(b[:4]) == "RIFF" && string(b[8:12]) == "WEBP":
		return "image/webp"
	}
	return ""
}
