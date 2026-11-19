package httpapi

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"
	"golang.org/x/crypto/bcrypt"

	"github.com/ggorockee/like-zzix/server/internal/admin"
	"github.com/ggorockee/like-zzix/server/internal/catalog"
	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/store"
	"github.com/ggorockee/like-zzix/server/internal/telemetry"
)

// 토큰 문자열 "valid:<email>"이면 그 이메일로 인증되는 가짜 검증기
type fakeVerifier struct{}

func (fakeVerifier) Verify(_ context.Context, token string) (string, error) {
	if e, ok := strings.CutPrefix(token, "valid:"); ok {
		return e, nil
	}
	return "", admin.ErrInvalidToken
}

type adminEnv struct {
	app    *fiber.App
	store  *store.Memory
	m      *telemetry.Metrics
	allow  admin.Allowlist
	cookie string
}

func newAdminEnv(t *testing.T, mods ...func(*AdminOptions)) *adminEnv {
	t.Helper()
	embedded, err := presets.Load()
	if err != nil {
		t.Fatal(err)
	}
	st := store.NewMemory()
	_, items, _ := presets.Embedded()
	orders := make([]int, len(items))
	for i := range orders {
		orders[i] = (i + 1) * 10
	}
	if _, err := st.SeedIfEmpty(context.Background(), items, orders, "seed"); err != nil {
		t.Fatal(err)
	}
	m := telemetry.New("test", "abc")
	holder := catalog.FromStore(st, embedded, m, nil)
	if err := holder.Refresh(context.Background()); err != nil {
		t.Fatal(err)
	}
	allow := admin.ParseAllowlist("boss@example.com")
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	opt := &AdminOptions{
		Store: st, Verifier: fakeVerifier{}, Allowlist: allow,
		Sessions: &admin.Sessions{Store: st, TTL: 3600e9},
		Origin:   "https://like-zzix-admin.woohalabs.com", GoogleClientID: "cid", CookieSecure: true,
		LoginLimit: 3,
	}
	for _, mod := range mods {
		mod(opt)
	}
	app := New(holder, Options{Metrics: m, Store: st, Log: quiet, Admin: opt})
	return &adminEnv{app: app, store: st, m: m, allow: allow}
}

func (e *adminEnv) do(t *testing.T, method, path, body string, headers ...string) (*http.Response, string) {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" && !strings.HasPrefix(body, "\xff") {
		req.Header.Set("Content-Type", "application/json")
	}
	for i := 0; i+1 < len(headers); i += 2 {
		req.Header.Set(headers[i], headers[i+1])
	}
	if e.cookie != "" {
		req.Header.Set("Cookie", e.cookie)
	}
	res, err := e.app.Test(req, -1)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(res.Body)
	return res, string(b)
}

func (e *adminEnv) login(t *testing.T, email string) *http.Response {
	t.Helper()
	res, _ := e.do(t, "POST", "/admin/v1/auth/google", `{"credential":"valid:`+email+`"}`)
	for _, c := range res.Cookies() {
		if c.Name == sessionCookie {
			e.cookie = c.Name + "=" + c.Value
		}
	}
	return res
}

func validDoc(id, title string) string {
	lm := "[" + strings.TrimSuffix(strings.Repeat("[0.5,0.5,0.9],", 33), ",") + "]"
	return `{"id":"` + id + `","category":"side","title":"` + title + `","tip":"팁","aspect_ratio":"3:4",` +
		`"camera":{"pitch_deg":0,"roll_deg":0},"pose":{"format":"blazepose33","coord":"normalized","landmarks":` + lm + `},` +
		`"outline":[[0.1,0.1],[0.9,0.1],[0.5,0.9]],"guide":["1단계"]}`
}

func TestAdminLogin(t *testing.T) {
	e := newAdminEnv(t)

	if res, body := e.do(t, "GET", "/admin/v1/config", ""); res.StatusCode != 200 || !strings.Contains(body, `"google_client_id":"cid"`) || !strings.Contains(body, `"dev_login":false`) {
		t.Fatalf("config: %d %s", res.StatusCode, body)
	}
	if res, _ := e.do(t, "GET", "/admin/v1/me", ""); res.StatusCode != 401 {
		t.Fatalf("me without session: %d", res.StatusCode)
	}
	if res := e.login(t, "stranger@example.com"); res.StatusCode != 403 || e.cookie != "" {
		t.Fatalf("not allowed: %d", res.StatusCode)
	}
	if res, _ := e.do(t, "POST", "/admin/v1/auth/google", `{"credential":"forged"}`); res.StatusCode != 401 {
		t.Fatalf("invalid token: %d", res.StatusCode)
	}

	res := e.login(t, "BOSS@example.com")
	if res.StatusCode != 200 {
		t.Fatalf("login: %d", res.StatusCode)
	}
	var cookie *http.Cookie
	for _, c := range res.Cookies() {
		if c.Name == sessionCookie {
			cookie = c
		}
	}
	if cookie == nil || !cookie.HttpOnly || !cookie.Secure || cookie.SameSite != http.SameSiteStrictMode || cookie.Path != "/admin" {
		t.Fatalf("session cookie flags: %+v", cookie)
	}
	if res, body := e.do(t, "GET", "/admin/v1/me", ""); res.StatusCode != 200 || !strings.Contains(body, "boss@example.com") {
		t.Fatalf("me: %d %s", res.StatusCode, body)
	}

	// 허용 목록에서 빠지면 남은 세션도 차단
	delete(e.allow, "boss@example.com")
	if res, _ := e.do(t, "GET", "/admin/v1/me", ""); res.StatusCode != 403 {
		t.Fatalf("revoked admin: %d", res.StatusCode)
	}
	e.allow["boss@example.com"] = true

	if res, _ := e.do(t, "POST", "/admin/v1/auth/logout", ""); res.StatusCode != 204 {
		t.Fatalf("logout: %d", res.StatusCode)
	}
	if res, _ := e.do(t, "GET", "/admin/v1/me", ""); res.StatusCode != 401 {
		t.Fatalf("after logout: %d", res.StatusCode)
	}

	m := scrape(t, e.m)
	for _, want := range []string{
		`likezzix_admin_logins_total{result="success"} 1`,
		`likezzix_admin_logins_total{result="not_allowed"} 1`,
		`likezzix_admin_logins_total{result="invalid_token"} 1`,
	} {
		if !strings.Contains(m, want) {
			t.Errorf("missing %s", want)
		}
	}
}

func TestAdminLoginRateLimit(t *testing.T) {
	e := newAdminEnv(t)
	for i := 0; i < 3; i++ {
		e.do(t, "POST", "/admin/v1/auth/google", `{"credential":"forged"}`)
	}
	if res, _ := e.do(t, "POST", "/admin/v1/auth/google", `{"credential":"valid:boss@example.com"}`); res.StatusCode != 429 {
		t.Fatalf("4th attempt in a minute: %d", res.StatusCode)
	}
	if !strings.Contains(scrape(t, e.m), `likezzix_admin_logins_total{result="rate_limited"} 1`) {
		t.Error("rate limit metric missing")
	}
}

func TestAdminDevLoginDisabledByDefault(t *testing.T) {
	e := newAdminEnv(t)
	if res, _ := e.do(t, "POST", "/admin/v1/auth/dev", ""); res.StatusCode == 200 {
		t.Fatal("dev login must not exist unless DevEmail is set")
	}
}

func TestAdminCORS(t *testing.T) {
	e := newAdminEnv(t)
	res, _ := e.do(t, "OPTIONS", "/admin/v1/presets", "",
		"Origin", "https://like-zzix-admin.woohalabs.com", "Access-Control-Request-Method", "PUT")
	if res.Header.Get("Access-Control-Allow-Origin") != "https://like-zzix-admin.woohalabs.com" ||
		res.Header.Get("Access-Control-Allow-Credentials") != "true" {
		t.Fatalf("cors: %v", res.Header)
	}
	res, _ = e.do(t, "OPTIONS", "/admin/v1/presets", "",
		"Origin", "https://evil.example.com", "Access-Control-Request-Method", "PUT")
	if res.Header.Get("Access-Control-Allow-Origin") != "" {
		t.Fatal("other origins must not be allowed")
	}
}

func TestAdminPresetLifecycle(t *testing.T) {
	e := newAdminEnv(t)
	if res, _ := e.do(t, "GET", "/admin/v1/presets", ""); res.StatusCode != 401 {
		t.Fatal("list requires login")
	}
	e.login(t, "boss@example.com")

	// 시드된 4개 + 검증 실패/ID 불일치
	if _, body := e.do(t, "GET", "/admin/v1/presets", ""); strings.Count(body, `"status":"published"`) != 4 {
		t.Fatalf("seeded list: %s", body)
	}
	if res, _ := e.do(t, "POST", "/admin/v1/presets", `{"doc":{"id":"Bad Id","title":"x"}}`); res.StatusCode != 422 {
		t.Fatalf("invalid doc: %d", res.StatusCode)
	}

	// 생성(초안) → 공개 목록에는 없음
	body := `{"doc":` + validDoc("new-pose", "새 포즈") + `,"sort_order":5}`
	if res, b := e.do(t, "POST", "/admin/v1/presets", body); res.StatusCode != 201 {
		t.Fatalf("create: %d %s", res.StatusCode, b)
	}
	if res, _ := e.do(t, "POST", "/admin/v1/presets", body); res.StatusCode != 409 {
		t.Fatalf("duplicate: %d", res.StatusCode)
	}
	if _, pub := e.do(t, "GET", "/v1/presets", ""); strings.Contains(pub, "new-pose") {
		t.Fatal("draft must not be public")
	}

	// 수정: 경로와 id가 다르면 거부
	if res, _ := e.do(t, "PUT", "/admin/v1/presets/other", body); res.StatusCode != 400 {
		t.Fatalf("id mismatch: %d", res.StatusCode)
	}
	upd := `{"doc":` + validDoc("new-pose", "수정된 포즈") + `,"sort_order":1}`
	if res, _ := e.do(t, "PUT", "/admin/v1/presets/new-pose", upd); res.StatusCode != 200 {
		t.Fatalf("update: %d", res.StatusCode)
	}

	// 사진: 형식 검사, 초안 사진은 공개 경로에서 안 보임
	if res, _ := e.do(t, "PUT", "/admin/v1/presets/new-pose/image", "\xffnot-an-image"); res.StatusCode != 415 {
		t.Fatalf("bad image: %d", res.StatusCode)
	}
	jpeg := "\xff\xd8\xff\xe0fake-jpeg-bytes"
	if res, _ := e.do(t, "PUT", "/admin/v1/presets/new-pose/image", jpeg); res.StatusCode != 200 {
		t.Fatalf("upload: %d", res.StatusCode)
	}
	if res, _ := e.do(t, "GET", "/v1/presets/new-pose/image", ""); res.StatusCode != 404 {
		t.Fatalf("draft image must not be public: %d", res.StatusCode)
	}
	if res, _ := e.do(t, "GET", "/admin/v1/presets/new-pose/image", ""); res.StatusCode != 200 {
		t.Fatalf("admin preview: %d", res.StatusCode)
	}

	// 공개 → 즉시 앱 API에 반영 (+ 사진 주소)
	if res, _ := e.do(t, "PATCH", "/admin/v1/presets/new-pose/status", `{"status":"published"}`); res.StatusCode != 200 {
		t.Fatalf("publish: %d", res.StatusCode)
	}
	_, pub := e.do(t, "GET", "/v1/presets", "")
	var list struct {
		Items []map[string]any `json:"items"`
	}
	_ = json.Unmarshal([]byte(pub), &list)
	if len(list.Items) != 5 || list.Items[0]["id"] != "new-pose" || list.Items[0]["title"] != "수정된 포즈" {
		t.Fatalf("published list: %s", pub)
	}
	url, _ := list.Items[0]["reference_url"].(string)
	if !strings.HasPrefix(url, "/v1/presets/new-pose/image?v=") {
		t.Fatalf("reference_url: %q", url)
	}
	res, img := e.do(t, "GET", url, "")
	if res.StatusCode != 200 || img != jpeg || res.Header.Get("Content-Type") != "image/jpeg" ||
		!strings.Contains(res.Header.Get("Cache-Control"), "immutable") {
		t.Fatalf("public image: %d %v", res.StatusCode, res.Header)
	}

	// 비공개 → 앱 목록에서 빠짐, 삭제
	e.do(t, "PATCH", "/admin/v1/presets/new-pose/status", `{"status":"draft"}`)
	if _, pub := e.do(t, "GET", "/v1/presets", ""); strings.Contains(pub, "new-pose") {
		t.Fatal("unpublished preset still public")
	}
	if res, _ := e.do(t, "DELETE", "/admin/v1/presets/new-pose", ""); res.StatusCode != 200 {
		t.Fatalf("delete: %d", res.StatusCode)
	}
	if res, _ := e.do(t, "DELETE", "/admin/v1/presets/new-pose", ""); res.StatusCode != 404 {
		t.Fatalf("delete twice: %d", res.StatusCode)
	}

	m := scrape(t, e.m)
	for _, want := range []string{
		`likezzix_admin_changes_total{action="create"} 1`,
		`likezzix_admin_changes_total{action="publish"} 1`,
		`likezzix_admin_changes_total{action="image"} 1`,
		`likezzix_presets{status="published"} 4`,
		`likezzix_db_up 1`,
	} {
		if !strings.Contains(m, want) {
			t.Errorf("missing %s", want)
		}
	}
}

func TestEventsBodyLimitStillApplies(t *testing.T) {
	e := newAdminEnv(t)
	big := `{"events":[{"name":"app_open","count":1,"preset":"` + strings.Repeat("x", 20000) + `"}]}`
	if res, _ := e.do(t, "POST", "/v1/events", big); res.StatusCode != 413 {
		t.Fatalf("oversized events: %d", res.StatusCode)
	}
}

func TestAdminPasswordLogin(t *testing.T) {
	e := newAdminEnv(t)
	if res, _ := e.do(t, "POST", "/admin/v1/auth/password", `{"id":"admin","password":"x"}`); res.StatusCode != 404 && res.StatusCode != 405 {
		t.Fatalf("password login must not exist unless configured: %d", res.StatusCode)
	}

	hash, _ := bcrypt.GenerateFromPassword([]byte("correct horse"), bcrypt.MinCost)
	pw, err := admin.NewPasswordLogin("admin", string(hash))
	if err != nil {
		t.Fatal(err)
	}
	e = newAdminEnv(t, func(o *AdminOptions) {
		o.Password = pw
		o.Allowlist["admin"] = true
	})

	if _, body := e.do(t, "GET", "/admin/v1/config", ""); !strings.Contains(body, `"password_login":true`) {
		t.Fatalf("config: %s", body)
	}
	for _, body := range []string{`{"id":"admin","password":"wrong"}`, `{"id":"root","password":"correct horse"}`} {
		if res, _ := e.do(t, "POST", "/admin/v1/auth/password", body); res.StatusCode != 401 {
			t.Fatalf("%s: %d", body, res.StatusCode)
		}
	}
	res, _ := e.do(t, "POST", "/admin/v1/auth/password", `{"id":"admin","password":"correct horse"}`)
	if res.StatusCode != 200 {
		t.Fatalf("login: %d", res.StatusCode)
	}
	for _, c := range res.Cookies() {
		if c.Name == sessionCookie {
			e.cookie = c.Name + "=" + c.Value
		}
	}
	if res, body := e.do(t, "GET", "/admin/v1/me", ""); res.StatusCode != 200 || !strings.Contains(body, `"admin"`) {
		t.Fatalf("me: %d %s", res.StatusCode, body)
	}
	if !strings.Contains(scrape(t, e.m), `likezzix_admin_logins_total{result="invalid_password"} 2`) {
		t.Error("invalid_password metric missing")
	}
}

func TestNewPasswordLoginRejectsPlaintext(t *testing.T) {
	if _, err := admin.NewPasswordLogin("admin", "plaintext"); err == nil {
		t.Fatal("plaintext must be rejected")
	}
	if p, err := admin.NewPasswordLogin("", ""); p != nil || err != nil {
		t.Fatal("empty config disables password login")
	}
}
