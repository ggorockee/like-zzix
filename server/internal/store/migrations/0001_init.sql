-- 프리셋: 앱 스키마 그대로의 JSON 문서(doc) + 관리 컬럼 + 레퍼런스 사진
CREATE TABLE presets (
    id          text PRIMARY KEY,
    doc         jsonb       NOT NULL,
    status      text        NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
    sort_order  integer     NOT NULL DEFAULT 0,
    image       bytea,
    image_type  text,
    image_etag  text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    updated_by  text        NOT NULL DEFAULT ''
);

CREATE INDEX presets_status_sort ON presets (status, sort_order);

-- 관리자 콘솔 세션 (토큰 원문은 저장하지 않고 SHA-256만 저장)
CREATE TABLE admin_sessions (
    token_hash  bytea PRIMARY KEY,
    email       text        NOT NULL,
    expires_at  timestamptz NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX admin_sessions_expires ON admin_sessions (expires_at);
