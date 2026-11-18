// Package store persists presets, their reference images and admin sessions.
//
// Postgres (Cloud SQL) in production; Memory for tests and local admin
// development. Both implement the same methods so handlers stay storage-agnostic.
package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"time"
)

// Status values of a preset.
const (
	StatusDraft     = "draft"
	StatusPublished = "published"
)

var (
	// ErrNotFound means the preset or session does not exist.
	ErrNotFound = errors.New("not found")
	// ErrExists means a preset with the same id already exists.
	ErrExists = errors.New("already exists")
)

// Preset is one stored preset. Doc is the app-facing JSON document.
type Preset struct {
	ID        string          `json:"id"`
	Doc       json.RawMessage `json:"doc"`
	Status    string          `json:"status"`
	SortOrder int             `json:"sort_order"`
	ImageETag string          `json:"image_etag,omitempty"`
	ImageType string          `json:"image_type,omitempty"`
	UpdatedAt time.Time       `json:"updated_at"`
	UpdatedBy string          `json:"updated_by"`
}

// Image is a stored reference image.
type Image struct {
	Data []byte
	Type string
	ETag string
}

// Session is an admin console session.
type Session struct {
	Email     string
	ExpiresAt time.Time
}

// Store is implemented by Postgres and Memory.
type Store interface {
	Ping(ctx context.Context) error

	ListPresets(ctx context.Context, onlyPublished bool) ([]Preset, error)
	GetPreset(ctx context.Context, id string) (Preset, error)
	// CreatePreset inserts a draft; ErrExists if the id is taken.
	CreatePreset(ctx context.Context, id string, doc json.RawMessage, sortOrder int, by string) error
	// UpdatePreset replaces the document (the id never changes).
	UpdatePreset(ctx context.Context, id string, doc json.RawMessage, sortOrder int, by string) error
	DeletePreset(ctx context.Context, id string) error
	SetStatus(ctx context.Context, id, status, by string) error
	// SeedIfEmpty inserts published presets when the table is empty; returns how many.
	SeedIfEmpty(ctx context.Context, docs []json.RawMessage, sortOrders []int, by string) (int, error)

	PutImage(ctx context.Context, id string, data []byte, contentType, by string) (etag string, err error)
	GetImage(ctx context.Context, id string) (Image, error)

	CreateSession(ctx context.Context, tokenHash []byte, s Session) error
	GetSession(ctx context.Context, tokenHash []byte) (Session, error)
	DeleteSession(ctx context.Context, tokenHash []byte) error
	DeleteExpiredSessions(ctx context.Context, now time.Time) (int64, error)
}

// ImageETag is a short content hash used for cache busting (?v=) and ETag headers.
func ImageETag(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:8])
}
