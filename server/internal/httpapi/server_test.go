package httpapi

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gofiber/fiber/v2"

	catalogpkg "github.com/ggorockee/like-zzix/server/internal/catalog"
	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/telemetry"
)

func newTestApp(t *testing.T) (*fiber.App, *telemetry.Metrics, *presets.Catalog) {
	t.Helper()
	catalog, err := presets.Load()
	if err != nil {
		t.Fatal(err)
	}
	m := telemetry.New("test", "abc")
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	return New(catalogpkg.Static(catalog, m), Options{Metrics: m, Log: quiet}), m, catalog
}

func do(t *testing.T, app *fiber.App, req *http.Request) (*http.Response, string) {
	t.Helper()
	res, err := app.Test(req, -1)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(res.Body)
	return res, string(body)
}

func TestPresetsListWithETag(t *testing.T) {
	app, _, catalog := newTestApp(t)

	res, body := do(t, app, httptest.NewRequest(http.MethodGet, "/v1/presets", nil))
	if res.StatusCode != 200 {
		t.Fatalf("status %d", res.StatusCode)
	}
	if res.Header.Get("ETag") != catalog.ETag() {
		t.Fatalf("etag %q", res.Header.Get("ETag"))
	}
	var doc struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal([]byte(body), &doc); err != nil || len(doc.Items) != catalog.Len() {
		t.Fatalf("items: %v %d", err, len(doc.Items))
	}
	// 앱이 쓰는 필드가 그대로 전달되는지
	for _, key := range []string{"guide", "outline", "reference_asset", "camera", "pose", "tip"} {
		if _, ok := doc.Items[0][key]; !ok {
			t.Errorf("missing field %q", key)
		}
	}

	req := httptest.NewRequest(http.MethodGet, "/v1/presets", nil)
	req.Header.Set("If-None-Match", catalog.ETag())
	res, body = do(t, app, req)
	if res.StatusCode != http.StatusNotModified || body != "" {
		t.Fatalf("want 304 with empty body, got %d %q", res.StatusCode, body)
	}
}

func TestPresetByID(t *testing.T) {
	app, _, catalog := newTestApp(t)
	id := catalog.IDs()[0]
	if res, body := do(t, app, httptest.NewRequest(http.MethodGet, "/v1/presets/"+id, nil)); res.StatusCode != 200 || !strings.Contains(body, id) {
		t.Fatalf("get %s: %d", id, res.StatusCode)
	}
	if res, _ := do(t, app, httptest.NewRequest(http.MethodGet, "/v1/presets/nope", nil)); res.StatusCode != 404 {
		t.Fatalf("want 404, got %d", res.StatusCode)
	}
}

func TestCategories(t *testing.T) {
	app, _, _ := newTestApp(t)
	res, body := do(t, app, httptest.NewRequest(http.MethodGet, "/v1/categories", nil))
	if res.StatusCode != 200 || !strings.Contains(body, "음료·카페") {
		t.Fatalf("categories: %d %s", res.StatusCode, body)
	}
}

func postEvents(t *testing.T, app *fiber.App, body string) (*http.Response, string) {
	req := httptest.NewRequest(http.MethodPost, "/v1/events", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-App-Platform", "android")
	req.Header.Set("X-App-Version", "1.0.0")
	return do(t, app, req)
}

func TestEventsCountedWithPresetFunnel(t *testing.T) {
	app, m, catalog := newTestApp(t)
	id := catalog.IDs()[0]
	res, body := postEvents(t, app, `{"events":[
		{"name":"preset_selected","count":3,"preset":"`+id+`"},
		{"name":"perfect_match","count":1,"preset":"`+id+`"},
		{"name":"photo_saved","count":1,"preset":"unknown-preset"},
		{"name":"app_open","count":1},
		{"name":"hacked","count":1},
		{"name":"app_open","count":9999}
	]}`)
	if res.StatusCode != http.StatusAccepted || !strings.Contains(body, `"accepted":4`) {
		t.Fatalf("got %d %s", res.StatusCode, body)
	}

	metrics := scrape(t, m)
	for _, want := range []string{
		`likezzix_app_events_total{event="preset_selected",platform="android"} 3`,
		`likezzix_preset_events_total{event="preset_selected",preset="` + id + `"} 3`,
		`likezzix_preset_events_total{event="perfect_match",preset="` + id + `"} 1`,
		`likezzix_app_events_total{event="photo_saved",platform="android"} 1`,
		`likezzix_app_events_rejected_total{reason="unknown_event"} 1`,
		`likezzix_app_events_rejected_total{reason="invalid_count"} 1`,
		`likezzix_app_requests_total{app_version="1.0.0",platform="android"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Errorf("missing %s", want)
		}
	}
	// 모르는 프리셋은 라벨로 만들지 않음 (카디널리티 제한)
	if strings.Contains(metrics, `preset="unknown-preset"`) {
		t.Error("unknown preset must not become a label")
	}
}

func TestEventsRejectsBadBatches(t *testing.T) {
	app, m, _ := newTestApp(t)
	if res, _ := postEvents(t, app, `not json`); res.StatusCode != 400 {
		t.Fatalf("malformed: %d", res.StatusCode)
	}
	if res, _ := postEvents(t, app, `{"events":[]}`); res.StatusCode != 400 {
		t.Fatalf("empty: %d", res.StatusCode)
	}
	metrics := scrape(t, m)
	for _, want := range []string{
		`likezzix_app_events_rejected_total{reason="malformed"} 1`,
		`likezzix_app_events_rejected_total{reason="batch_size"} 1`,
	} {
		if !strings.Contains(metrics, want) {
			t.Errorf("missing %s", want)
		}
	}
}

func TestHTTPMetricsUseRoutePattern(t *testing.T) {
	app, m, catalog := newTestApp(t)
	do(t, app, httptest.NewRequest(http.MethodGet, "/v1/presets/"+catalog.IDs()[0], nil))
	do(t, app, httptest.NewRequest(http.MethodGet, "/random/scanner/path", nil))
	metrics := scrape(t, m)
	if !strings.Contains(metrics, `route="/v1/presets/:id",status="200"`) {
		t.Error("route pattern label missing")
	}
	if !strings.Contains(metrics, `route="unmatched",status="404"`) {
		t.Error("unmatched route must collapse into one label")
	}
	if strings.Contains(metrics, "/random/scanner") {
		t.Error("raw paths must not become labels")
	}
}

func TestHealthAndPrivacy(t *testing.T) {
	app, _, _ := newTestApp(t)
	for _, path := range []string{"/healthz", "/readyz"} {
		if res, _ := do(t, app, httptest.NewRequest(http.MethodGet, path, nil)); res.StatusCode != 200 {
			t.Fatalf("%s: %d", path, res.StatusCode)
		}
	}
	res, body := do(t, app, httptest.NewRequest(http.MethodGet, "/privacy", nil))
	if res.StatusCode != 200 || !strings.Contains(body, "라익찍스 개인정보처리방침") {
		t.Fatalf("privacy: %d", res.StatusCode)
	}
	res, body = do(t, app, httptest.NewRequest(http.MethodGet, "/support", nil))
	if res.StatusCode != 200 || !strings.Contains(body, "라익찍스 고객지원") {
		t.Fatalf("support: %d", res.StatusCode)
	}
}

func scrape(t *testing.T, m *telemetry.Metrics) string {
	t.Helper()
	_, body := do(t, NewMetricsApp(m), httptest.NewRequest(http.MethodGet, "/metrics", nil))
	return body
}
