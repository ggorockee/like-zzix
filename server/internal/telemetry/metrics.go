// Package telemetry exposes Prometheus metrics for the server and anonymous
// app activity. kube-prometheus-stack scrapes them via a ServiceMonitor
// (infra: charts/helm/prod/like-zzix).
//
// Every label has a bounded value set: routes come from the router's pattern
// (never the raw path), platforms and event names are allowlisted, preset ids
// must exist in the catalog, and app versions that do not look like semver
// collapse into "other".
package telemetry

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
)

const namespace = "likezzix"

// Metrics holds every collector on a private registry.
type Metrics struct {
	Registry *prometheus.Registry

	httpRequests *prometheus.CounterVec
	httpDuration *prometheus.HistogramVec
	httpInFlight prometheus.Gauge
	appRequests  *prometheus.CounterVec
	appEvents    *prometheus.CounterVec
	presetEvents *prometheus.CounterVec
	eventsReject *prometheus.CounterVec
	presetsCount *prometheus.GaugeVec
	adminLogins  *prometheus.CounterVec
	adminChanges *prometheus.CounterVec
	dbUp         prometheus.Gauge
	dbErrors     *prometheus.CounterVec
	refreshes    *prometheus.CounterVec
	lastRefresh  prometheus.Gauge
}

// New registers all collectors. version and commit label likezzix_build_info.
func New(version, commit string) *Metrics {
	reg := prometheus.NewRegistry()
	m := &Metrics{Registry: reg}
	f := func(c prometheus.Collector) { reg.MustRegister(c) }

	f(collectors.NewGoCollector())
	f(collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}))

	buildInfo := prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: namespace, Name: "build_info", Help: "Build metadata; value is always 1.",
	}, []string{"version", "commit"})
	buildInfo.WithLabelValues(version, commit).Set(1)
	f(buildInfo)

	m.httpRequests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "http_requests_total", Help: "HTTP requests by route pattern and status.",
	}, []string{"method", "route", "status"})
	m.httpDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Namespace: namespace, Name: "http_request_duration_seconds", Help: "HTTP request latency.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
	}, []string{"method", "route"})
	m.httpInFlight = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: namespace, Name: "http_requests_in_flight", Help: "HTTP requests being served.",
	})
	m.appRequests = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "app_requests_total",
		Help: "API requests from the mobile app by platform and app version (from X-App-* headers).",
	}, []string{"platform", "app_version"})
	m.appEvents = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "app_events_total", Help: "Anonymous in-app activity events reported by the app.",
	}, []string{"event", "platform"})
	m.presetEvents = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "preset_events_total",
		Help: "Preset funnel events (selected, perfect match, saved) by preset id.",
	}, []string{"event", "preset"})
	m.eventsReject = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "app_events_rejected_total", Help: "Activity events or batches rejected.",
	}, []string{"reason"})
	m.presetsCount = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Namespace: namespace, Name: "presets", Help: "Number of presets by status (published = served by /v1/presets).",
	}, []string{"status"})
	m.adminLogins = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "admin_logins_total",
		Help: "Admin console login attempts (success, not_allowed, invalid_token, invalid_password, rate_limited).",
	}, []string{"result"})
	m.adminChanges = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "admin_changes_total",
		Help: "Preset changes made in the admin console (create, update, delete, publish, unpublish, image).",
	}, []string{"action"})
	m.dbUp = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: namespace, Name: "db_up", Help: "1 if the last database check succeeded, 0 if it failed, -1 when no database is configured.",
	})
	m.dbErrors = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "db_errors_total", Help: "Database errors by operation.",
	}, []string{"op"})
	m.refreshes = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: namespace, Name: "catalog_refreshes_total",
		Help: "Preset catalog reloads from the database (ok, error). On error the last good catalog keeps serving.",
	}, []string{"result"})
	m.lastRefresh = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: namespace, Name: "catalog_last_success_timestamp_seconds",
		Help: "Unix time of the last successful catalog reload (0 in static mode).",
	})

	for _, c := range []prometheus.Collector{
		m.httpRequests, m.httpDuration, m.httpInFlight, m.appRequests, m.appEvents,
		m.presetEvents, m.eventsReject, m.presetsCount, m.adminLogins, m.adminChanges,
		m.dbUp, m.dbErrors, m.refreshes, m.lastRefresh,
	} {
		f(c)
	}

	// Pre-create series so rate() and dashboards show 0 instead of "no data".
	for event := range AllowedEvents {
		for _, p := range []string{"android", "ios"} {
			m.appEvents.WithLabelValues(event, p)
		}
	}
	for _, r := range []string{"malformed", "batch_size", "unknown_event", "invalid_count"} {
		m.eventsReject.WithLabelValues(r)
	}
	for _, r := range []string{"success", "not_allowed", "invalid_token", "invalid_password", "rate_limited"} {
		m.adminLogins.WithLabelValues(r)
	}
	for _, a := range []string{"create", "update", "delete", "publish", "unpublish", "image"} {
		m.adminChanges.WithLabelValues(a)
	}
	for _, r := range []string{"ok", "error"} {
		m.refreshes.WithLabelValues(r)
	}
	m.dbUp.Set(-1)
	return m
}

// SetPresets records published/draft counts and pre-creates the funnel series per published preset.
func (m *Metrics) SetPresets(ids []string, drafts int) {
	m.presetsCount.WithLabelValues("published").Set(float64(len(ids)))
	m.presetsCount.WithLabelValues("draft").Set(float64(drafts))
	for _, id := range ids {
		for event := range PresetEvents {
			m.presetEvents.WithLabelValues(event, id)
		}
	}
}

// HTTP records one request.
func (m *Metrics) HTTP(method, route string, status int, seconds float64) {
	m.httpRequests.WithLabelValues(method, route, statusCode(status)).Inc()
	m.httpDuration.WithLabelValues(method, route).Observe(seconds)
}

// InFlight adjusts the in-flight gauge by delta.
func (m *Metrics) InFlight(delta float64) { m.httpInFlight.Add(delta) }

// AppRequest counts a request carrying app headers.
func (m *Metrics) AppRequest(platform, version string) {
	m.appRequests.WithLabelValues(NormalizePlatform(platform), NormalizeVersion(version)).Inc()
}

// AppEvent counts n occurrences of an allowlisted event.
func (m *Metrics) AppEvent(event, platform string, n int) {
	m.appEvents.WithLabelValues(event, NormalizePlatform(platform)).Add(float64(n))
}

// PresetEvent counts n funnel events for a known preset.
func (m *Metrics) PresetEvent(event, preset string, n int) {
	m.presetEvents.WithLabelValues(event, preset).Add(float64(n))
}

// EventRejected counts a rejected event or batch.
func (m *Metrics) EventRejected(reason string) { m.eventsReject.WithLabelValues(reason).Inc() }

var semver = regexp.MustCompile(`^\d{1,3}\.\d{1,3}\.\d{1,4}$`)

// NormalizePlatform maps the X-App-Platform header to ios, android, other or none.
func NormalizePlatform(p string) string {
	switch p = strings.ToLower(strings.TrimSpace(p)); p {
	case "ios", "android":
		return p
	case "":
		return "none"
	default:
		return "other"
	}
}

// NormalizeVersion keeps x.y.z versions and maps anything else to "other" ("none" if empty).
func NormalizeVersion(v string) string {
	v = strings.TrimSpace(v)
	switch {
	case v == "":
		return "none"
	case semver.MatchString(v):
		return v
	default:
		return "other"
	}
}

func statusCode(code int) string {
	if code < 100 || code > 599 {
		return "other"
	}
	return strconv.Itoa(code)
}

// AdminLogin counts a login attempt by result.
func (m *Metrics) AdminLogin(result string) { m.adminLogins.WithLabelValues(result).Inc() }

// AdminChange counts a preset change made in the admin console.
func (m *Metrics) AdminChange(action string) { m.adminChanges.WithLabelValues(action).Inc() }

// DBUp records the result of the last database check.
func (m *Metrics) DBUp(ok bool) {
	if ok {
		m.dbUp.Set(1)
	} else {
		m.dbUp.Set(0)
	}
}

// DBError counts a failed database operation.
func (m *Metrics) DBError(op string) { m.dbErrors.WithLabelValues(op).Inc() }

// CatalogRefreshed records a catalog reload; unix is the success time.
func (m *Metrics) CatalogRefreshed(ok bool, unix float64) {
	if ok {
		m.refreshes.WithLabelValues("ok").Inc()
		m.lastRefresh.Set(unix)
		return
	}
	m.refreshes.WithLabelValues("error").Inc()
}
