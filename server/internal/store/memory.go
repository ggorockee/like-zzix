package store

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"sort"
	"sync"
	"time"
)

// Memory is an in-process Store for tests and local admin development.
// Data is lost on restart.
type Memory struct {
	mu       sync.Mutex
	presets  map[string]*memPreset
	sessions map[string]Session
	now      func() time.Time
}

type memPreset struct {
	Preset
	image []byte
}

// NewMemory returns an empty in-memory store.
func NewMemory() *Memory {
	return &Memory{presets: map[string]*memPreset{}, sessions: map[string]Session{}, now: time.Now}
}

func (m *Memory) Ping(context.Context) error { return nil }

func (m *Memory) ListPresets(_ context.Context, onlyPublished bool) ([]Preset, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var out []Preset
	for _, p := range m.presets {
		if onlyPublished && p.Status != StatusPublished {
			continue
		}
		out = append(out, p.Preset)
	}
	sort.Slice(out, func(a, b int) bool {
		if out[a].SortOrder != out[b].SortOrder {
			return out[a].SortOrder < out[b].SortOrder
		}
		return out[a].ID < out[b].ID
	})
	return out, nil
}

func (m *Memory) GetPreset(_ context.Context, id string) (Preset, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.presets[id]
	if !ok {
		return Preset{}, ErrNotFound
	}
	return p.Preset, nil
}

func (m *Memory) CreatePreset(_ context.Context, id string, doc json.RawMessage, sortOrder int, by string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.presets[id]; ok {
		return ErrExists
	}
	m.presets[id] = &memPreset{Preset: Preset{
		ID: id, Doc: append(json.RawMessage(nil), doc...), Status: StatusDraft,
		SortOrder: sortOrder, UpdatedAt: m.now(), UpdatedBy: by,
	}}
	return nil
}

func (m *Memory) UpdatePreset(_ context.Context, id string, doc json.RawMessage, sortOrder int, by string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.presets[id]
	if !ok {
		return ErrNotFound
	}
	p.Doc, p.SortOrder, p.UpdatedBy, p.UpdatedAt = append(json.RawMessage(nil), doc...), sortOrder, by, m.now()
	return nil
}

func (m *Memory) DeletePreset(_ context.Context, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if _, ok := m.presets[id]; !ok {
		return ErrNotFound
	}
	delete(m.presets, id)
	return nil
}

func (m *Memory) SetStatus(_ context.Context, id, status, by string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.presets[id]
	if !ok {
		return ErrNotFound
	}
	p.Status, p.UpdatedBy, p.UpdatedAt = status, by, m.now()
	return nil
}

func (m *Memory) SeedIfEmpty(_ context.Context, docs []json.RawMessage, sortOrders []int, by string) (int, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if len(m.presets) > 0 {
		return 0, nil
	}
	for i, doc := range docs {
		var head struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(doc, &head); err != nil {
			return 0, err
		}
		m.presets[head.ID] = &memPreset{Preset: Preset{
			ID: head.ID, Doc: append(json.RawMessage(nil), doc...), Status: StatusPublished,
			SortOrder: sortOrders[i], UpdatedAt: m.now(), UpdatedBy: by,
		}}
	}
	return len(docs), nil
}

func (m *Memory) PutImage(_ context.Context, id string, data []byte, contentType, by string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.presets[id]
	if !ok {
		return "", ErrNotFound
	}
	etag := ImageETag(data)
	p.image = append([]byte(nil), data...)
	p.ImageType, p.ImageETag, p.UpdatedBy, p.UpdatedAt = contentType, etag, by, m.now()
	return etag, nil
}

func (m *Memory) GetImage(_ context.Context, id string) (Image, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.presets[id]
	if !ok || len(p.image) == 0 {
		return Image{}, ErrNotFound
	}
	return Image{Data: p.image, Type: p.ImageType, ETag: p.ImageETag}, nil
}

func (m *Memory) CreateSession(_ context.Context, tokenHash []byte, s Session) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.sessions[hex.EncodeToString(tokenHash)] = s
	return nil
}

func (m *Memory) GetSession(_ context.Context, tokenHash []byte) (Session, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	s, ok := m.sessions[hex.EncodeToString(tokenHash)]
	if !ok {
		return Session{}, ErrNotFound
	}
	return s, nil
}

func (m *Memory) DeleteSession(_ context.Context, tokenHash []byte) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	delete(m.sessions, hex.EncodeToString(tokenHash))
	return nil
}

func (m *Memory) DeleteExpiredSessions(_ context.Context, now time.Time) (int64, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var n int64
	for k, s := range m.sessions {
		if s.ExpiresAt.Before(now) {
			delete(m.sessions, k)
			n++
		}
	}
	return n, nil
}

var (
	_ Store = (*Memory)(nil)
	_ Store = (*Postgres)(nil)
)
