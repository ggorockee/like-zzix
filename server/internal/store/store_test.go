package store

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"
)

// 같은 계약을 Memory와 Postgres(TEST_DATABASE_URL이 있을 때)에 모두 적용한다.
func TestMemoryContract(t *testing.T) { runContract(t, NewMemory()) }

func TestPostgresContract(t *testing.T) {
	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx := context.Background()
	pg, err := OpenPostgres(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pg.Close)
	if _, err := pg.Migrate(ctx); err != nil {
		t.Fatal(err)
	}
	// 두 번째 실행은 아무것도 적용하지 않아야 한다.
	if again, err := pg.Migrate(ctx); err != nil || len(again) != 0 {
		t.Fatalf("migrate twice: %v %v", again, err)
	}
	if _, err := pg.pool.Exec(ctx, `TRUNCATE presets, admin_sessions`); err != nil {
		t.Fatal(err)
	}
	runContract(t, pg)
}

func runContract(t *testing.T, s Store) {
	ctx := context.Background()
	doc := func(id string) json.RawMessage { return json.RawMessage(`{"id":"` + id + `","title":"t"}`) }

	// 시드: 비어 있을 때만, 공개 상태로
	n, err := s.SeedIfEmpty(ctx, []json.RawMessage{doc("b"), doc("a")}, []int{20, 10}, "seed")
	if err != nil || n != 2 {
		t.Fatalf("seed: %d %v", n, err)
	}
	if n, _ := s.SeedIfEmpty(ctx, []json.RawMessage{doc("c")}, []int{1}, "seed"); n != 0 {
		t.Fatal("seed must be skipped when not empty")
	}
	list, _ := s.ListPresets(ctx, true)
	if len(list) != 2 || list[0].ID != "a" || list[0].Status != StatusPublished {
		t.Fatalf("published list by sort_order: %+v", list)
	}

	// 생성은 초안, 중복 id는 ErrExists
	if err := s.CreatePreset(ctx, "new", doc("new"), 5, "admin@x"); err != nil {
		t.Fatal(err)
	}
	if err := s.CreatePreset(ctx, "new", doc("new"), 5, "admin@x"); !errors.Is(err, ErrExists) {
		t.Fatalf("duplicate: %v", err)
	}
	if pub, _ := s.ListPresets(ctx, true); len(pub) != 2 {
		t.Fatal("draft must not be published")
	}
	if all, _ := s.ListPresets(ctx, false); len(all) != 3 || all[0].ID != "new" {
		t.Fatalf("all: %+v", all)
	}

	// 수정·공개
	if err := s.UpdatePreset(ctx, "new", json.RawMessage(`{"id":"new","title":"수정"}`), 1, "admin@x"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetStatus(ctx, "new", StatusPublished, "admin@x"); err != nil {
		t.Fatal(err)
	}
	got, err := s.GetPreset(ctx, "new")
	if err != nil || got.Status != StatusPublished || got.UpdatedBy != "admin@x" {
		t.Fatalf("get: %+v %v", got, err)
	}
	var d map[string]any
	_ = json.Unmarshal(got.Doc, &d)
	if d["title"] != "수정" {
		t.Fatalf("doc not updated: %s", got.Doc)
	}

	// 사진
	if _, err := s.GetImage(ctx, "new"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("no image yet: %v", err)
	}
	etag, err := s.PutImage(ctx, "new", []byte{0xff, 0xd8, 1, 2}, "image/jpeg", "admin@x")
	if err != nil || etag != ImageETag([]byte{0xff, 0xd8, 1, 2}) {
		t.Fatalf("put image: %s %v", etag, err)
	}
	img, err := s.GetImage(ctx, "new")
	if err != nil || img.Type != "image/jpeg" || len(img.Data) != 4 || img.ETag != etag {
		t.Fatalf("get image: %+v %v", img, err)
	}
	if p, _ := s.GetPreset(ctx, "new"); p.ImageETag != etag {
		t.Fatal("preset must expose image etag")
	}

	// 없는 대상
	for name, err := range map[string]error{
		"update": s.UpdatePreset(ctx, "zzz", doc("zzz"), 0, "x"),
		"delete": s.DeletePreset(ctx, "zzz"),
		"status": s.SetStatus(ctx, "zzz", StatusDraft, "x"),
	} {
		if !errors.Is(err, ErrNotFound) {
			t.Errorf("%s missing: %v", name, err)
		}
	}
	if _, err := s.PutImage(ctx, "zzz", []byte{1}, "image/jpeg", "x"); !errors.Is(err, ErrNotFound) {
		t.Errorf("put image missing: %v", err)
	}

	// 삭제
	if err := s.DeletePreset(ctx, "new"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.GetPreset(ctx, "new"); !errors.Is(err, ErrNotFound) {
		t.Fatal("deleted preset still exists")
	}

	// 세션
	now := time.Now().UTC().Truncate(time.Second)
	live, old := []byte("live-hash"), []byte("old-hash")
	_ = s.CreateSession(ctx, live, Session{Email: "a@x", ExpiresAt: now.Add(time.Hour)})
	_ = s.CreateSession(ctx, old, Session{Email: "b@x", ExpiresAt: now.Add(-time.Hour)})
	if got, err := s.GetSession(ctx, live); err != nil || got.Email != "a@x" {
		t.Fatalf("session: %+v %v", got, err)
	}
	if n, _ := s.DeleteExpiredSessions(ctx, now); n != 1 {
		t.Fatalf("expired deleted: %d", n)
	}
	_ = s.DeleteSession(ctx, live)
	if _, err := s.GetSession(ctx, live); !errors.Is(err, ErrNotFound) {
		t.Fatal("session must be gone")
	}
}
