# admin/ - 관리자 콘솔

> 기준: Nuxt 4.6 (`ssr: false` 정적 SPA) + Nuxt UI 4.12 + `@mediapipe/tasks-vision` 1.2.3 · 주소 https://like-zzix-admin.woohalabs.com
> 백엔드는 Go API 서버의 `/admin/v1` (별도 백엔드 없음). 데이터는 Cloud SQL `like_zzix` DB.

## 1. 역할

관리자 콘솔의 핵심은 **프리셋(구도) 제작 도구**. "레퍼런스 사진 업로드 → 브라우저에서 포즈·외곽선 추출 → 앱과 같은 화면으로 미리보기 → 저장 → 공개" 흐름.

| 기능 | 현재 구현 |
|------|------|
| 로그인 | "Google로 로그인" 버튼 → OpenID Connect 리디렉션(`response_type=id_token`, state·nonce 확인) → `/login#id_token=...` → `POST /admin/v1/auth/google`(ID 토큰 검증) → `ADMIN_EMAILS` 허용 목록에 있는 이메일만 세션 쿠키 발급. Google 기본 버튼은 로그인된 계정 이름을 표시해서 쓰지 않음 |
| 예비 로그인 | 아이디/비밀번호 1개 계정 (`ADMIN_LOGIN_ID`, `ADMIN_PASSWORD_HASH`=bcrypt, GSM 보관). 둘 다 있을 때만 `POST /admin/v1/auth/password`가 열리고 화면에 입력칸이 보임. 로그인 시도 제한(분당 5회) 공유, 실패는 `invalid_password` 지표. 해시는 `go run ./cmd/hashpw`(표준 입력으로 비밀번호)로 만든다 |
| 프리셋 목록 | 사진 썸네일, 카테고리, 앱 공개 스위치, 정렬 순서, 최근 수정(시각·관리자) |
| 프리셋 편집기 | 사진 선택 → 긴 변 1080px JPEG로 축소(1.5MB 이하) → MediaPipe로 관절 33개·인물 마스크 추출 → 외곽선(폐곡선) 생성 → 미리보기 → ID·제목·카테고리·팁·권장 각도·단계별 가이드 입력 → 저장 |
| 앱 미리보기 | 앱 카메라 화면과 같은 방식: 사진(투명도 조절, 기본 40%) + 흰색 인물 외곽선 + 비교 관절 13개 |
| 공개/비공개 | 저장은 항상 비공개(draft)로 시작. 공개(published)한 프리셋만 앱 `/v1/presets`에 내려감. 30초 안에 반영 |
| 삭제 | 확인 모달 후 사진·포즈 데이터 함께 삭제 (되돌릴 수 없음) |
| 모니터링 링크 | 상단 메뉴에 Grafana 대시보드(like-zzix) 바로가기 |

광고 플래그·버전 관리는 Firebase Console(Remote Config)에서 관리하므로 콘솔에 중복 구현하지 않음.

## 2. 데이터 흐름

| 단계 | 처리 |
|------|------|
| 저장 | 콘솔 → `POST/PUT /admin/v1/presets/{id}` (프리셋 JSON, 서버가 `presets.Validate`로 앱과 같은 스키마 검증) → `PUT /admin/v1/presets/{id}/image` (JPEG/PNG/WebP, 1.5MB 이하, 내용으로 형식 판별) |
| 저장소 | Cloud SQL `presets` 테이블 (문서 jsonb + 사진 bytea + 사진 ETag + 수정자). 세션은 `admin_sessions` (토큰 원문 대신 SHA-256만 저장) |
| 앱 반영 | 서버가 30초마다 공개 프리셋을 다시 읽어 메모리 카탈로그 교체. 사진이 있으면 `reference_url`(`/v1/presets/{id}/image?v=ETag`)을 붙임. DB 장애 시 마지막 정상본 유지 |
| 앱 표시 | 앱은 `reference_url`이 있으면 서버 사진, 실패하면 번들 사진, 그것도 없으면 관절 실루엣 |
| 첫 기동 | DB가 비어 있으면 서버에 포함된 기본 프리셋 4개를 공개 상태로 넣음 (사진 없이 포즈·외곽선만) |

## 3. 왜 브라우저에서 포즈를 추출하는가

| 방식 | 판단 |
|------|------|
| 콘솔 브라우저에서 MediaPipe Pose Landmarker (heavy 모델) | ✅ 채택. 앱 ML Kit과 같은 BlazePose 33점 → 좌표 호환, 서버는 Go만 유지, 결과를 바로 보고 다시 올릴 수 있음 |
| Go 서버에서 추출 | Go용 ML 런타임·모델 운영 부담 |
| 앱에서 매번 추출 | 프리셋마다 첫 로딩 지연, 잘못 추출돼도 보정 불가 |

주의: MediaPipe 웹 라이브러리는 CPU 모드에서도 WebGL로 이미지를 변환함. 그래픽 가속이 꺼진 브라우저에서는 추출이 안 되며 콘솔이 해결 방법(Chrome 설정 > 시스템 > 그래픽 가속 사용)을 안내함.

## 4. 보안

| 항목 | 내용 |
|------|------|
| 인증 | Google ID 토큰 서명(JWKS)·audience(웹 클라이언트 ID)·issuer·만료·email_verified 검증 |
| 권한 | `ADMIN_EMAILS` 허용 목록(GSM 보관, 공개 저장소에 없음). 요청마다 다시 확인하므로 목록에서 빼면 기존 세션도 즉시 차단 |
| 세션 | 32바이트 난수 토큰, 쿠키 `lzx_admin` (HttpOnly, Secure, SameSite=Strict, Path=/admin), 12시간 |
| 남용 방지 | 로그인 분당 5회 제한, CORS는 콘솔 주소 하나만 허용(credentials) |
| 개발용 로그인 | `ADMIN_DEV_EMAIL`은 `APP_ENV=local`일 때만 허용 (운영에서 설정하면 서버가 기동 실패) |
| 사진 저작권 | 직접 촬영했거나 권한 있는 사진만 업로드 (콘솔 안내 문구). `claudedocs/images`의 참고 사진은 서버에 올리지 않음 |
| 검색 노출 | robots noindex, nginx `X-Robots-Tag`, 프레임 삽입 차단 |

## 5. 폴더 구조

| 경로 | 내용 |
|------|------|
| `app/pages/login.vue` | Google로 로그인 버튼, 아이디/비밀번호 로그인, 로컬에서는 개발용 로그인 |
| `app/pages/presets/index.vue` | 목록 (`UTable` + `USwitch`) |
| `app/pages/presets/[id].vue` | 편집기 (`new` = 새 프리셋) |
| `app/components/PosePreview.vue` | 사진+외곽선+관절 Canvas 미리보기 |
| `app/composables/useApi.ts` | `$fetch` + credentials, 401이면 로그인 화면으로, 한국어 오류 메시지 |
| `app/composables/useAuth.ts` | 세션 확인·로그인·로그아웃 |
| `app/composables/usePoseExtractor.ts` | MediaPipe 지연 로딩(처음 한 번), 관절·마스크 추출 |
| `app/utils/outline.ts` | 마스크 → 가장 큰 영역 → 경계 추적 → 단순화된 외곽선 (vitest) |
| `app/utils/image.ts`, `app/utils/preset.ts` | 사진 축소, 프리셋 타입·검증 |
| `Dockerfile`, `nginx.conf` | `nuxi generate` → nginx(비루트, 읽기 전용 루트), `/healthz`, SPA 폴백. `absolute_redirect off` + `$uri/index.html`로 `/login` 직접 접속 시 내부 포트(:8080) 리다이렉트 방지 |

## 6. 로컬 실행

| 순서 | 내용 |
|------|------|
| 1 | Postgres 실행 (예: docker postgres:15-alpine) |
| 2 | 서버: `APP_ENV=local`, `POSTGRES_*`, `ADMIN_EMAILS=dev@local`, `ADMIN_DEV_EMAIL=dev@local`, `ADMIN_ORIGIN=http://localhost:3000` 로 `go run ./cmd/api` (DB 없이 실행하면 메모리 저장소) |
| 3 | 콘솔: `admin/`에서 `npm install` 후 `npm run dev` (API 주소 기본값 http://localhost:18080, 바꾸려면 `NUXT_PUBLIC_API_BASE`) |
| 4 | http://localhost:3000 → "개발용 로그인" |

## 7. 작업 체크리스트

### A1. 기반
- [x] Nuxt 4 SPA + Nuxt UI 레이아웃 (한국어)
- [x] Google 로그인 (허용 목록) / 인증 미들웨어
- [x] Go API `/admin/v1` + Cloud SQL 저장소 + 지표(로그인·변경·DB·갱신)
- [ ] 사용자 관리 페이지 (스태프·슈퍼계정 → 앱 광고 면제) — SNS 로그인 단계(`feature/sns-auth`)에서

### A2. 프리셋 관리
- [x] 목록 / 공개 전환 / 정렬 순서 / 삭제
- [x] 사진 업로드 (DB 저장, 공개 API로 ETag 캐시 제공)
- [ ] 드래그 정렬
- [ ] 카테고리 관리 (현재 4개 고정: 전신샷·부르고 찍기·옆모습·음료·카페)

### A3. 포즈 편집기
- [x] MediaPipe Pose Landmarker 연동 (33점 정규화 좌표 + 인물 외곽선)
- [x] 앱과 같은 방식의 미리보기 (투명도·관절 표시 조절)
- [ ] 관절 드래그 보정
- [ ] 휴대폰 프레임(9:19.5) 미리보기

### A4. 배포
- [x] Dockerfile / nginx / CI(`ci-admin.yml`: 검사 → 이미지 → infra `admin.image.tag` PR)
- [x] infra: Terraform DB·사용자, ExternalSecret, 관리자 Deployment·Service, VirtualService, blackbox, 대시보드·알림
- [x] GSM `prod-like-zzix-credentials` 생성 (2026-11-19 확인: ExternalSecret `SecretSynced`, DB·ADMIN_EMAILS·GOOGLE_CLIENT_ID 주입)
- [x] OAuth 웹 클라이언트(yanggo-514212, woohalabs11 계정)에 승인된 JS 출처 `https://like-zzix-admin.woohalabs.com` 추가 (2026-11-19). 동의 화면이 "테스트 중"이라 테스트 사용자(현재 woohaen88)만 로그인 가능 → 다른 관리자 계정은 대상 > 테스트 사용자에 추가 필요
- [x] 같은 OAuth 클라이언트에 승인된 리디렉션 URI `https://like-zzix-admin.woohalabs.com/login` 추가 (2026-11-19)
- [x] GSM `prod-like-zzix-credentials`에 `ADMIN_LOGIN_ID`·`ADMIN_PASSWORD_HASH` 추가, 원문 비밀번호는 별도 시크릿 `prod-like-zzix-admin-password`에 보관
- [x] 포즈 추출 중단 수정: MediaPipe(CPU·마스크)는 입력 폭이 4의 배수가 아니면 WASM이 Aborted → `fitSize`로 폭을 4의 배수로 맞춤 (원본 사진 4장 E2E 통과)
