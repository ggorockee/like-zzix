package store

import (
	"context"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

//go:embed migrations/*.sql
var migrationFS embed.FS

// Postgres stores everything in PostgreSQL.
type Postgres struct {
	pool *pgxpool.Pool
}

// OpenPostgres connects and verifies the connection.
func OpenPostgres(ctx context.Context, dsn string) (*Postgres, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("store: parse dsn: %w", err)
	}
	// Cloud SQL max_connections 100 is shared by every service; keep this small.
	cfg.MaxConns = 4
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("store: connect: %w", err)
	}
	pctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := pool.Ping(pctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("store: ping: %w", err)
	}
	return &Postgres{pool: pool}, nil
}

// Close releases the pool.
func (p *Postgres) Close() { p.pool.Close() }

// Ping checks the database (readiness probe).
func (p *Postgres) Ping(ctx context.Context) error { return p.pool.Ping(ctx) }

// Migrate applies pending migrations/*.sql in order, each in a transaction.
// An advisory lock keeps two starting pods from migrating at once.
func (p *Postgres) Migrate(ctx context.Context) (applied []string, err error) {
	conn, err := p.pool.Acquire(ctx)
	if err != nil {
		return nil, err
	}
	defer conn.Release()
	const lockID = 7215489 // like-zzix migrations
	if _, err := conn.Exec(ctx, `SELECT pg_advisory_lock($1)`, lockID); err != nil {
		return nil, err
	}
	defer func() { _, _ = conn.Exec(context.Background(), `SELECT pg_advisory_unlock($1)`, lockID) }()

	if _, err := conn.Exec(ctx, `CREATE TABLE IF NOT EXISTS schema_migrations (
		version integer PRIMARY KEY, name text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())`); err != nil {
		return nil, err
	}
	names, err := fs.Glob(migrationFS, "migrations/*.sql")
	if err != nil {
		return nil, err
	}
	sort.Strings(names)
	for _, name := range names {
		base := strings.TrimPrefix(name, "migrations/")
		version, err := strconv.Atoi(strings.SplitN(base, "_", 2)[0])
		if err != nil {
			return applied, fmt.Errorf("store: migration %s: version prefix: %w", base, err)
		}
		var done bool
		if err := conn.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM schema_migrations WHERE version = $1)`, version).Scan(&done); err != nil {
			return applied, err
		}
		if done {
			continue
		}
		sqlText, err := migrationFS.ReadFile(name)
		if err != nil {
			return applied, err
		}
		tx, err := conn.Begin(ctx)
		if err != nil {
			return applied, err
		}
		if _, err := tx.Exec(ctx, string(sqlText)); err != nil {
			_ = tx.Rollback(ctx)
			return applied, fmt.Errorf("store: migration %s: %w", base, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version, name) VALUES ($1, $2)`, version, base); err != nil {
			_ = tx.Rollback(ctx)
			return applied, err
		}
		if err := tx.Commit(ctx); err != nil {
			return applied, err
		}
		applied = append(applied, base)
	}
	return applied, nil
}

const presetColumns = `id, doc, status, sort_order, COALESCE(image_etag, ''), COALESCE(image_type, ''), updated_at, updated_by`

func scanPreset(row pgx.Row) (Preset, error) {
	var p Preset
	err := row.Scan(&p.ID, &p.Doc, &p.Status, &p.SortOrder, &p.ImageETag, &p.ImageType, &p.UpdatedAt, &p.UpdatedBy)
	if errors.Is(err, pgx.ErrNoRows) {
		return p, ErrNotFound
	}
	return p, err
}

func (p *Postgres) ListPresets(ctx context.Context, onlyPublished bool) ([]Preset, error) {
	q := `SELECT ` + presetColumns + ` FROM presets`
	if onlyPublished {
		q += ` WHERE status = 'published'`
	}
	q += ` ORDER BY sort_order, id`
	rows, err := p.pool.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Preset
	for rows.Next() {
		item, err := scanPreset(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (p *Postgres) GetPreset(ctx context.Context, id string) (Preset, error) {
	return scanPreset(p.pool.QueryRow(ctx, `SELECT `+presetColumns+` FROM presets WHERE id = $1`, id))
}

func (p *Postgres) CreatePreset(ctx context.Context, id string, doc json.RawMessage, sortOrder int, by string) error {
	_, err := p.pool.Exec(ctx,
		`INSERT INTO presets (id, doc, sort_order, updated_by) VALUES ($1, $2, $3, $4)`, id, doc, sortOrder, by)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return ErrExists
	}
	return err
}

func (p *Postgres) UpdatePreset(ctx context.Context, id string, doc json.RawMessage, sortOrder int, by string) error {
	return expectOne(p.pool.Exec(ctx,
		`UPDATE presets SET doc = $2, sort_order = $3, updated_by = $4, updated_at = now() WHERE id = $1`,
		id, doc, sortOrder, by))
}

func (p *Postgres) DeletePreset(ctx context.Context, id string) error {
	return expectOne(p.pool.Exec(ctx, `DELETE FROM presets WHERE id = $1`, id))
}

func (p *Postgres) SetStatus(ctx context.Context, id, status, by string) error {
	return expectOne(p.pool.Exec(ctx,
		`UPDATE presets SET status = $2, updated_by = $3, updated_at = now() WHERE id = $1`, id, status, by))
}

func (p *Postgres) SeedIfEmpty(ctx context.Context, docs []json.RawMessage, sortOrders []int, by string) (int, error) {
	tx, err := p.pool.Begin(ctx)
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var count int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM presets`).Scan(&count); err != nil {
		return 0, err
	}
	if count > 0 {
		return 0, nil
	}
	for i, doc := range docs {
		var head struct {
			ID string `json:"id"`
		}
		if err := json.Unmarshal(doc, &head); err != nil {
			return 0, err
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO presets (id, doc, status, sort_order, updated_by) VALUES ($1, $2, 'published', $3, $4)`,
			head.ID, doc, sortOrders[i], by); err != nil {
			return 0, err
		}
	}
	return len(docs), tx.Commit(ctx)
}

func (p *Postgres) PutImage(ctx context.Context, id string, data []byte, contentType, by string) (string, error) {
	etag := ImageETag(data)
	return etag, expectOne(p.pool.Exec(ctx,
		`UPDATE presets SET image = $2, image_type = $3, image_etag = $4, updated_by = $5, updated_at = now() WHERE id = $1`,
		id, data, contentType, etag, by))
}

func (p *Postgres) GetImage(ctx context.Context, id string) (Image, error) {
	var img Image
	var data []byte
	err := p.pool.QueryRow(ctx,
		`SELECT image, COALESCE(image_type, ''), COALESCE(image_etag, '') FROM presets WHERE id = $1`, id).
		Scan(&data, &img.Type, &img.ETag)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && len(data) == 0) {
		return img, ErrNotFound
	}
	img.Data = data
	return img, err
}

func (p *Postgres) CreateSession(ctx context.Context, tokenHash []byte, s Session) error {
	_, err := p.pool.Exec(ctx,
		`INSERT INTO admin_sessions (token_hash, email, expires_at) VALUES ($1, $2, $3)`, tokenHash, s.Email, s.ExpiresAt)
	return err
}

func (p *Postgres) GetSession(ctx context.Context, tokenHash []byte) (Session, error) {
	var s Session
	err := p.pool.QueryRow(ctx,
		`SELECT email, expires_at FROM admin_sessions WHERE token_hash = $1`, tokenHash).Scan(&s.Email, &s.ExpiresAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return s, ErrNotFound
	}
	return s, err
}

func (p *Postgres) DeleteSession(ctx context.Context, tokenHash []byte) error {
	_, err := p.pool.Exec(ctx, `DELETE FROM admin_sessions WHERE token_hash = $1`, tokenHash)
	return err
}

func (p *Postgres) DeleteExpiredSessions(ctx context.Context, now time.Time) (int64, error) {
	tag, err := p.pool.Exec(ctx, `DELETE FROM admin_sessions WHERE expires_at < $1`, now)
	return tag.RowsAffected(), err
}

func expectOne(tag pgconn.CommandTag, err error) error {
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
