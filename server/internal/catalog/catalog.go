// Package catalog keeps the published preset list in memory.
//
// In database mode it reloads from the store periodically and after admin
// changes. A failed reload keeps the last good catalog, so a database outage
// never takes /v1/presets down (the app also has its bundled fallback).
package catalog

import (
	"context"
	"encoding/json"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/ggorockee/like-zzix/server/internal/presets"
	"github.com/ggorockee/like-zzix/server/internal/store"
	"github.com/ggorockee/like-zzix/server/internal/telemetry"
)

// Holder serves the current catalog.
type Holder struct {
	cur     atomic.Pointer[presets.Catalog]
	store   store.Store
	metrics *telemetry.Metrics
	log     *slog.Logger
	now     func() time.Time
}

// Static serves a fixed catalog (embedded presets, no database).
func Static(c *presets.Catalog, m *telemetry.Metrics) *Holder {
	h := &Holder{metrics: m, log: slog.Default(), now: time.Now}
	h.cur.Store(c)
	if m != nil {
		m.SetPresets(c.IDs(), 0)
	}
	return h
}

// FromStore starts with initial (embedded presets) and reloads from s.
func FromStore(s store.Store, initial *presets.Catalog, m *telemetry.Metrics, log *slog.Logger) *Holder {
	h := Static(initial, m)
	h.store, h.log = s, log
	return h
}

// Current returns the catalog to serve.
func (h *Holder) Current() *presets.Catalog { return h.cur.Load() }

// ImagePath is the public image URL of a preset (relative to the API base URL).
func ImagePath(id, etag string) string { return "/v1/presets/" + id + "/image?v=" + etag }

// Refresh reloads published presets. On error the previous catalog stays.
func (h *Holder) Refresh(ctx context.Context) error {
	if h.store == nil {
		return nil
	}
	err := h.refresh(ctx)
	if h.metrics != nil {
		h.metrics.DBUp(err == nil)
		h.metrics.CatalogRefreshed(err == nil, float64(h.now().Unix()))
		if err != nil {
			h.metrics.DBError("catalog_refresh")
		}
	}
	return err
}

func (h *Holder) refresh(ctx context.Context) error {
	rows, err := h.store.ListPresets(ctx, false)
	if err != nil {
		return err
	}
	var docs []json.RawMessage
	var ids []string
	drafts := 0
	var version time.Time
	for _, r := range rows {
		if r.Status != store.StatusPublished {
			drafts++
			continue
		}
		doc := r.Doc
		if r.ImageETag != "" {
			if doc, err = withField(doc, "reference_url", ImagePath(r.ID, r.ImageETag)); err != nil {
				return err
			}
		}
		docs = append(docs, doc)
		ids = append(ids, r.ID)
		if r.UpdatedAt.After(version) {
			version = r.UpdatedAt
		}
	}
	c, err := presets.Build(version.UTC().Format(time.RFC3339), docs)
	if err != nil {
		return err
	}
	h.cur.Store(c)
	if h.metrics != nil {
		h.metrics.SetPresets(ids, drafts)
	}
	return nil
}

// Run reloads every interval until ctx ends.
func (h *Holder) Run(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			rctx, cancel := context.WithTimeout(ctx, 10*time.Second)
			if err := h.Refresh(rctx); err != nil {
				h.log.Warn("catalog refresh failed; serving last good catalog", "err", err)
			}
			cancel()
		}
	}
}

func withField(doc json.RawMessage, key, value string) (json.RawMessage, error) {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(doc, &m); err != nil {
		return nil, err
	}
	v, _ := json.Marshal(value)
	m[key] = v
	return json.Marshal(m)
}
