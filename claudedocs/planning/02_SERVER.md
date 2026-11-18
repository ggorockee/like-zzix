# server/ - Go API 서버 설계

> 기준: Go 1.26 / Fiber v2 · 원칙: **백엔드는 Go만 사용**, **모니터링되지 않는 것은 관리될 수 없다**

## 0. 현재 구현 상태 (2026-11-18, S1 MVP 배포 완료)

운영 중인 yen-back 서버와 같은 구조로 먼저 배포하고, DB·관리자 API는 admin 단계에서 추가한다. 아래 1~6장은 최종 목표 설계.

| 항목 | 현재 | 최종 목표 |
|------|------|-----------|
| 프레임워크 | Fiber v2 (yen-back과 동일, 운영 검증된 adaptor·promhttp 조합) | 동일 유지 (v3 전환은 별도 검토) |
| 프리셋 저장 | 이미지에 포함한 JSON (`internal/presets/presets.json` = 앱 번들 파일, 다르면 테스트 실패) | PostgreSQL (admin에서 등록) |
| 배포 | `https://like-zzix.woohalabs.com`, GKE `like-zzix` 네임스페이스, ArgoCD 앱 `like-zzix` | 동일 |
| 이미지 | Docker Hub `ggorockee/like-zzix-server`, CI가 main 머지 시 빌드 → infra 태그 PR 자동 머지 | 동일 |

| Method | Path | 설명 |
|--------|------|------|
| GET | `/healthz`, `/readyz` | K8s probe, blackbox 외부 검사 |
| GET | `/v1/presets` | 전체 프리셋 (ETag, `If-None-Match` → 304, `Cache-Control: public, max-age=300`) |
| GET | `/v1/presets/:id` | 단건, 없으면 404 |
| GET | `/v1/categories` | 프리셋이 있는 카테고리와 개수 |
| POST | `/v1/events` | 앱 익명 사용 이벤트 묶음 (최대 40개, 허용 목록 외 거부) → 202 |
| GET | `/privacy` | 개인정보처리방침 (web `/privacy` 전까지 스토어 등록용) |
| GET | `/metrics` | 별도 포트 9090, VirtualService로 노출하지 않음 |

| 지표 (`likezzix_`) | 라벨 | 용도 |
|--------------------|------|------|
| `http_requests_total`, `http_request_duration_seconds` | method, route(패턴), status | 요청 수·지연·5xx |
| `app_requests_total` | platform, app_version | 앱 버전 분포 (강제 업데이트 후 구버전 잔존 확인) |
| `app_events_total` | event, platform | 앱 실행, 프리셋 선택, Perfect Match, 저장/실패, 카메라 불가, 갤러리, 업데이트 팝업 반응 |
| `preset_events_total` | event, preset | 촬영 퍼널 (선택 → Perfect Match → 저장), 카탈로그에 있는 프리셋만 |
| `app_events_rejected_total` | reason | 앱·서버 허용 목록 불일치 감지 |
| `build_info`, `presets` | version, commit | 배포 버전, 제공 프리셋 수 |

라벨 상한 원칙: 원본 경로 대신 라우트 패턴, 허용 목록에 없는 이벤트는 거부, 모르는 프리셋은 라벨로 만들지 않음, semver가 아닌 버전은 `other`.

## 1. 역할

| 대상 | 기능 |
|------|------|
| mobile (공개) | 프리셋·카테고리 조회 (읽기 전용, 인증 없음, ETag 캐시) |
| mobile (인증) | SNS 로그인 검증 → 토큰 발급, 내 정보(`is_staff`/`is_superuser`), 로그아웃, 회원 탈퇴 |
| admin (superuser) | 프리셋 CRUD, 이미지 업로드 URL 발급, 공개/비공개 전환, 정렬, **사용자 역할 관리** |
| web (공개) | 공유 페이지용 프리셋 단건 조회 |

Remote Config / 광고 플래그는 Firebase Console에서 관리하므로 서버에 구현하지 않음.

## 2. 기술 스택

| 영역 | 선택 | 이유 |
|------|------|------|
| 프레임워크 | Fiber v3 | PRD 지정 |
| DB | PostgreSQL 17 | 프리셋 메타 + 포즈 좌표(JSONB) |
| DB 접근 | `pgx/v5` + `sqlc` | SQL 그대로 작성, 타입 안전 코드 생성, ORM 미사용 |
| 마이그레이션 | `goose` | SQL 파일 기반 |
| 스토리지 | S3 호환 (S3 / GCS / R2) + CDN | 이미지 직접 서빙하지 않음 (presigned PUT 업로드) |
| 설정 | 환경변수 (`caarlos0/env`) | 12-factor, K8s Secret 연동 |
| 로깅 | `log/slog` (JSON) | 표준 라이브러리 |
| 앱 인증 | access JWT(HS256, 15분, `golang-jwt/jwt/v5`) + refresh 불투명 토큰(30일, 회전, DB에는 SHA-256 해시만 저장) | 앱은 쿠키를 쓰지 않음. refresh 재사용 감지 시 같은 계열 전체 폐기 |
| SNS 검증 | Google·Apple: JWKS 서명 검증(`MicahParks/keyfunc/v3`) + `iss`/`aud`/`exp`, Apple은 `nonce`=sha256(raw). Kakao: `GET kapi.kakao.com/v1/user/access_token_info`의 `app_id` 일치 확인 후 `/v2/user/me` | 클라이언트가 보낸 사용자 ID를 신뢰하지 않음 |
| 관리자 인증 | Google 로그인(GIS ID 토큰) → `is_superuser`·`is_active`만 허용 → 서버 세션 쿠키 (HttpOnly, Secure, SameSite=Strict, 12시간) | 관리자 비밀번호 없음, 앱과 같은 `users` 테이블 사용. Python/Django 미사용 |
| 테스트 | `testing` + `testcontainers-go`(Postgres) | 실제 DB로 통합 테스트 |

## 3. 폴더 구조

| 경로 | 내용 |
|------|------|
| `cmd/api/main.go` | 진입점, 설정 로드, 의존성 조립, graceful shutdown |
| `internal/config/` | 환경변수 구조체 |
| `internal/http/` | Fiber 라우터, 미들웨어(recover, requestid, CORS, rate limit, 세션) |
| `internal/http/handler/` | `preset_handler.go`, `auth_handler.go`, `admin_auth_handler.go`, `admin_preset_handler.go`, `admin_user_handler.go`, `health_handler.go` |
| `internal/auth/` | SNS 검증기(google/kakao/apple), 토큰 발급·회전, 미들웨어(`RequireUser`, `RequireSuperuser`) |
| `cmd/grant-superuser/` | 최초 슈퍼계정 지정 CLI (`--email` 또는 `--user-id`) |
| `internal/preset/` | 도메인 서비스 + 검증 (landmarks 33개, 좌표 0~1 범위 등) |
| `internal/storage/` | S3 presigned URL 발급 |
| `internal/db/` | `queries/*.sql`, sqlc 생성 코드 |
| `migrations/` | goose SQL |
| `deploy/k8s/` | `deployment.yaml`, `service.yaml`, `ingress.yaml`, `configmap.yaml` |
| `Dockerfile` | 멀티스테이지: golang 빌드 → alpine 런타임 (PRD Step 6) |

## 4. 데이터 모델

| 테이블 | 주요 컬럼 |
|--------|-----------|
| `categories` | `id`(slug), `name`, `sort_order` |
| `presets` | `id`(slug), `category_id`, `title`, `tip`, `aspect_ratio`, `camera_pitch_deg`, `camera_roll_deg`, `pose`(JSONB), `thumbnail_key`, `silhouette_key`, `source_key`(원본, 비공개), `status`(draft/published), `sort_order`, `created_at`, `updated_at` |
| `users` | `id`(uuid), `email`(nullable), `name`, `is_staff`, `is_superuser`, `is_active`, `created_at`, `last_login_at` |
| `user_identities` | `user_id`, `provider`(kakao/google/apple), `subject`(제공자 고유 ID), `email`, `apple_refresh_token`(암호화, 탈퇴 시 revoke용), `created_at` · UNIQUE(`provider`, `subject`) |
| `refresh_tokens` | `token_hash`, `user_id`, `family_id`, `expires_at`, `revoked_at` |
| `admin_sessions` | `token_hash`, `user_id`, `expires_at` (콘솔 쿠키 세션) |

계정 식별은 `provider`+`subject` 단위. 이메일이 같아도 자동 병합하지 않음 (카카오 이메일은 미인증일 수 있음).

## 5. API

| Method | Path | 인증 | 설명 |
|--------|------|------|------|
| GET | `/healthz`, `/readyz` | - | K8s probe (readyz는 DB ping 포함) |
| GET | `/v1/categories` | - | 카테고리 목록 |
| GET | `/v1/presets?category=` | - | 공개 프리셋 목록, `ETag` + `Cache-Control: public, max-age=300` |
| GET | `/v1/presets/:id` | - | 단건 (web 공유 페이지·딥링크용) |
| POST | `/v1/auth/kakao` | - | 본문 `access_token` → 토큰 쌍 + user (rate limit 10회/분/IP) |
| POST | `/v1/auth/google` | - | 본문 `id_token` |
| POST | `/v1/auth/apple` | - | 본문 `identity_token`, `authorization_code`, `nonce`, `full_name`(선택). code로 Apple refresh token 교환 후 암호화 보관 |
| POST | `/v1/auth/refresh` | - | 본문 `refresh_token` → 새 토큰 쌍 (회전) |
| POST | `/v1/auth/logout` | - | 본문 `refresh_token` 폐기 |
| GET | `/v1/auth/me` | Bearer | user (`is_staff`, `is_superuser` 포함) |
| DELETE | `/v1/auth/me` | Bearer | 회원 탈퇴: Apple revoke / Kakao unlink(Admin Key) 후 사용자·식별자·토큰 삭제 |
| POST | `/admin/v1/auth/google` | - | GIS ID 토큰 → superuser만 세션 쿠키 발급 (rate limit 5회/분) |
| POST | `/admin/v1/auth/logout` | 세션 | |
| GET | `/admin/v1/users?q=&role=` | 세션 | 사용자 검색 (이메일/이름, 역할 필터) |
| PATCH | `/admin/v1/users/:id` | 세션 | `is_staff`, `is_superuser`, `is_active` 변경. 자기 자신의 superuser 해제 금지 (잠김 방지) |
| GET | `/admin/v1/presets` | 세션 | draft 포함 목록 |
| POST | `/admin/v1/presets` | 세션 | 생성 |
| PUT | `/admin/v1/presets/:id` | 세션 | 수정 (포즈 좌표 포함) |
| DELETE | `/admin/v1/presets/:id` | 세션 | 삭제 |
| PATCH | `/admin/v1/presets/:id/status` | 세션 | 공개/비공개 |
| POST | `/admin/v1/uploads` | 세션 | presigned PUT URL 발급 (`image/webp`, `image/png`, `image/jpeg`, 10MB 제한) |

목록 응답 예시 (프리셋 객체 스키마는 `01_MOBILE.md` 5장과 동일):

{"version":"2026-11-18T00:00:00Z","items":[{"id":"full-body-low-angle","category":"full_body","title":"전신샷"}]}

에러 응답 형식:

{"error":{"code":"PRESET_NOT_FOUND","message":"preset not found"}}

인증 응답 (`/v1/auth/{provider}`, `/v1/auth/refresh`):

{"access_token":"eyJ...","refresh_token":"rt_...","user":{"id":"8f1c...","login_method":"kakao","email":"a@b.c","name":"홍길동","is_staff":false,"is_superuser":false}}

## 6. 배포 (PRD Step 6)

| 항목 | 값 |
|------|-----|
| 컨테이너 포트 | 3000 |
| 이미지 | alpine 기반, non-root 사용자, CGO 비활성 정적 바이너리 |
| replicas | 2 |
| resources | requests cpu 50m / mem 64Mi, limits cpu 500m / mem 256Mi |
| probe | liveness `/healthz`, readiness `/readyz` |
| Service | ClusterIP 80 → 3000, Ingress에서 `api.` 서브도메인 연결 |
| 비밀값 | DB URL, S3 키, JWT 서명 키, 세션 시크릿, Apple 로그인 키(.p8), Kakao Admin Key, 토큰 암호화 키 → K8s Secret |

## 7. 작업 체크리스트

### S1. 공개 API
- [x] `go mod init`, Fiber v2, 설정/slog JSON 로그/graceful shutdown, 메트릭 전용 포트
- [x] `/v1/categories`, `/v1/presets`, `/v1/presets/:id` + ETag (임베드 JSON)
- [x] `/v1/events` 앱 사용 이벤트 + 프리셋 퍼널 지표
- [x] 단위·HTTP 테스트 (gofmt, vet, staticcheck, race)
- [ ] goose 마이그레이션 + sqlc 설정 (admin 단계에서 DB 도입 시)
- [ ] 통합 테스트 (testcontainers, DB 도입 시)

### S1.5 앱 인증 (마지막 단계, mobile M7과 계약 일치)
- [ ] `users`, `user_identities`, `refresh_tokens` 마이그레이션
- [ ] SNS 검증기: Google ID 토큰 / Kakao app_id / Apple 서명·nonce (단위 테스트: 위조·타 앱 토큰 거부)
- [ ] `/v1/auth/{kakao,google,apple}`, `/refresh`(회전·재사용 감지), `/logout`, `GET·DELETE /me`
- [ ] 회원 탈퇴 시 Apple revoke, Kakao unlink
- [ ] 최초 슈퍼계정 지정 CLI (`cmd/grant-superuser`)

### S2. 관리자 API
- [ ] `/admin/v1/auth/google` (superuser만) + 세션 미들웨어 + rate limit
- [ ] 사용자 검색 / 역할(`is_staff`, `is_superuser`, `is_active`) 변경
- [ ] 프리셋 CRUD + 포즈 데이터 검증
- [ ] presigned 업로드 URL
- [ ] CORS: admin 도메인만 허용

### S3. 배포 (infra PR #1178)
- [x] Dockerfile (멀티스테이지, distroless non-root, 12MB)
- [x] infra 차트 `charts/helm/prod/like-zzix` (Deployment, Service, ConfigMap, ServiceMonitor) + ArgoCD `apps-like-zzix-cfg.yaml`
- [x] Istio VirtualService `like-zzix.woohalabs.com` (기존 와일드카드 인증서·DNS)
- [x] 클러스터: 기존 GKE `woohalabs-prod-gke`
- [x] CI: lint·test → 이미지 푸시 → infra 태그 PR 자동 머지 (`.github/workflows/ci-server.yml`)
- [x] 모니터링: Grafana `like-zzix` 대시보드, 알림 `like-zzix.server`·`like-zzix.app`, blackbox 외부 검사 (`06_OPERATIONS.md`)
