# 라익찍스 (Like ZZIX) - 모노레포 전체 설계

> 기준일: 2026-11-18 · 원본: `claudedocs/PRD_MASTER.md`
> 진행 순서: **mobile 프로토타입 → server → admin → web → 계정(SNS 로그인·광고 면제)**
> 대전제: **모니터링되지 않는 것은 관리될 수 없다** — 새 기능은 지표·대시보드·알림과 함께 배포 (`06_OPERATIONS.md`)

## 1. 모노레포 구성

| 폴더 | 역할 | 기술 스택 | 배포 형태 | 상세 문서 |
|------|------|-----------|-----------|-----------|
| `mobile/` | AR 실루엣 가이드 카메라 앱 (핵심 제품) | Flutter 3.47 / Dart 3.13 / Riverpod 3 | App Store / Play Store | `01_MOBILE.md` |
| `server/` | 프리셋 API + 관리자 API | Go 1.26 / Fiber v3 / PostgreSQL | Docker → Kubernetes | `02_SERVER.md` |
| `admin/` | 프리셋(구도) 등록·관리 콘솔 | Nuxt 4 (SPA 모드) + Nuxt UI 4 + MediaPipe Tasks Vision | 정적 빌드 → CDN 또는 nginx 컨테이너 | `04_ADMIN.md` |
| `web/` | 랜딩 / 개인정보처리방침 / 이용약관 / 딥링크 | Nuxt 4 (SSG) + Nuxt UI 4 | 정적 빌드 → CDN | `03_WEB.md` |

## 2. 시스템 아키텍처

| 흐름 | 설명 |
|------|------|
| admin → server | 관리자가 레퍼런스 이미지를 업로드하면 **브라우저에서 MediaPipe로 33개 관절 좌표를 추출**하고, 이미지와 좌표를 서버에 저장 |
| server → 오브젝트 스토리지 | 이미지/실루엣 썸네일은 S3(또는 GCS)에 저장, CDN으로 서빙 |
| mobile → server | 앱 시작 시 `GET /v1/presets` 호출 (ETag 캐시), 실패 시 앱 번들 기본 프리셋 사용 |
| mobile → server (인증) | SNS(카카오/Google/Apple) 자격 증명을 서버가 검증 → 자체 토큰 발급. `GET /v1/auth/me`의 `is_staff`/`is_superuser`로 광고 면제 판단 |
| admin → server (인증) | Google 로그인 → `is_superuser` 사용자만 콘솔 세션 발급 (별도 관리자 비밀번호 없음) |
| mobile → Firebase | Remote Config(광고 플래그·버전 정책), Crashlytics |
| mobile → server (지표) | 앱 익명 사용 이벤트·버전 헤더 → Prometheus → Grafana `like-zzix` 대시보드·Alertmanager 메일 |
| mobile → AdMob | Remote Config 플래그가 true일 때만 광고 로드 |
| web → 스토어 | 랜딩에서 스토어 링크, 프리셋 공유 링크(`/p/{id}`) → 앱 딥링크 |

## 3. 핵심 기술 결정 (ADR 요약)

| # | 결정 | 이유 | 대안 |
|---|------|------|------|
| 1 | 상태 관리는 **Riverpod 3**로 통일 | Provider 대비 테스트 용이, 코드 생성 없이도 사용 가능, 비동기(AsyncValue) 처리 일관 | Provider (PRD 허용) |
| 2 | 포즈 좌표계는 **BlazePose 33 랜드마크**로 통일 | ML Kit Pose(모바일)와 MediaPipe Pose Landmarker(웹/admin)가 동일한 33점 토폴로지 사용 → admin에서 추출한 좌표를 앱에서 그대로 사용 가능 | 서버(Go)에서 추출 → Go에 ML 런타임 필요, 비효율 |
| 3 | 좌표는 **이미지 기준 정규화(0~1)** 로 저장 | 해상도/화면비와 무관하게 재사용 | 픽셀 좌표 |
| 4 | web/admin 프레임워크는 **Nuxt 4 하나로 통일** | 1인 개발 기준 학습·유지 비용 최소화, web은 SSG·admin은 SPA로 모드만 다르게 사용, 둘 다 Node 서버 없이 정적 배포 → 백엔드는 오직 Go | Next.js 16 (아래 4장 참고) |
| 5 | **SNS 로그인은 선택 사항** (카카오/Google/Apple). 사람 단위로 `is_staff`/`is_superuser`를 부여하고, 둘 중 하나라도 true면 광고 전부 OFF | 운영진·지인을 사람 단위로 구분해 광고 면제. 로그인 없이도 촬영 기능 전부 사용 가능 (Apple 5.1.1) | 계정 없음(초기안), 관계자 전용 이메일 로그인 |
| 7 | 인증은 **Go 서버가 직접 발급** (access JWT 15분 + refresh 30일 회전). SNS 토큰은 서버에서 검증: Google ID 토큰 `aud`, Kakao `app_id`, Apple 서명·`aud`·`nonce` | 사용자/역할의 단일 진실 공급원을 Go DB로 유지, Firebase Auth는 카카오 미지원(커스텀 토큰 필요), reviewmaps와 같은 구조. reviewmaps의 Google access token 방식은 다른 앱 토큰 재사용이 가능해 ID 토큰으로 강화 | Firebase Auth + custom claims |
| 8 | 관리자 콘솔은 **Python/Django 없이 Nuxt SPA + Go Admin API**. 로그인은 Google 로그인 후 `is_superuser`만 허용, HttpOnly 세션 쿠키 | 비밀번호 저장·유출 위험 없음, 앱과 같은 `users` 테이블로 역할 관리, 백엔드 언어 1개 유지 (reviewmaps의 Django admin은 별도 런타임·속도 문제) | Django admin, 별도 관리자 비밀번호 계정 |
| 6 | 프리셋 이미지는 **자체 촬영/라이선스 확보 이미지만** 사용 | `claudedocs/images/`의 참고 이미지는 인스타그램 게시물(타인 저작물·초상)로 배포 불가. 프로토타입에서는 로컬 빌드에만 넣고(git 제외), 저장소에는 추출한 포즈 좌표·윤곽선만 포함. 출시 전 교체 | 실루엣 라인 드로잉만 배포 |

## 4. web/admin 프레임워크 선택 근거

| 기준 | Nuxt 4 (Vue) | Next.js 16 (React) | Vue 3 + Vite (순수 SPA) |
|------|--------------|--------------------|-------------------------|
| 정적 사이트(SSG) | `nuxt generate` 지원 | `output: export` 지원 | SEO 약함 |
| 관리자 SPA | `ssr: false`로 SPA 빌드 | 가능하나 App Router가 서버 기능 중심 | 가장 단순 |
| 관리자 UI 키트 | Nuxt UI 4 (Dashboard/Table/Form 컴포넌트 포함, 무료) | shadcn/ui + TanStack Table (조립 필요) | Element Plus, PrimeVue |
| web + admin 단일 스택 | ✅ | ✅ | ❌ (web은 SEO 문제) |
| 학습 곡선 | 낮음 (템플릿 문법 직관적) | 중간 (RSC/서버 액션 개념) | 낮음 |
| 생태계·채용·AI 도구 지원 | 중간 | 가장 큼 | 중간 |

**권장: Nuxt 4 통일.** 백엔드를 Go로 고정했기 때문에 Next.js의 강점(서버 컴포넌트, 서버 액션, Vercel 통합)을 거의 사용하지 않음. React 경험이 더 많다면 Next.js 16 + shadcn/ui로 바꿔도 구조(정적 web + SPA admin + Go API)는 동일하게 유지됨.

관리자 패널 대안 검토:

| 옵션 | 판단 |
|------|------|
| Nuxt UI 기반 직접 구현 | ✅ 채택. 프리셋 등록 시 MediaPipe 포즈 추출·실루엣 미리보기 등 커스텀 화면이 핵심이라 범용 어드민 툴로는 부족 |
| Refine / React-Admin | CRUD는 빠르지만 커스텀 포즈 편집 화면에서 결국 직접 구현 필요 |
| Directus / Strapi 같은 Headless CMS | 백엔드가 Node로 추가됨 → "백엔드는 Go만" 원칙 위배 |
| Firebase Console만 사용 | Remote Config는 Firebase Console에서 관리 (admin에 중복 구현하지 않음) |

## 5. 로드맵

| 단계 | 범위 | 상태 |
|------|------|------|
| M0 | mobile 프로젝트 생성, 폴더 구조, 린트, Firebase 연결 | [x] |
| M1 | Remote Config + AdMob 초기화 | [x] |
| M2 | 카메라 화면 + 프리셋 시트 + 실루엣 오버레이 + 촬영·저장 (화면 MVP) | [x] |
| M3·M4 | 레퍼런스 오버레이, ML Kit 실시간 포즈 매칭, 각도 가이드, Perfect Match | [x] |
| M5 | 무음/크롭, 전면 광고, 설정 화면 | [ ] |
| S1·S3 | server 프리셋 API·앱 이벤트 지표, Docker/K8s 배포, 대시보드·알림 (`02_SERVER.md`, `06_OPERATIONS.md`) | [x] |
| S2 | admin API (DB 도입). 사용자 관리는 S1.5 이후 | [x] |
| A1~A3 | admin 로그인, 프리셋 CRUD, 포즈 추출 (`04_ADMIN.md`). 운영 배포 완료, OAuth JS 출처 등록·보강 항목(드래그 정렬 등)은 `04_ADMIN.md` | [x] |
| W1~W2 | web 랜딩, 정책 페이지, 딥링크 (`03_WEB.md`) | [ ] |
| M7·S1.5 | SNS 로그인 + `is_staff`/`is_superuser` 광고 면제 (마지막, 클라이언트는 `feature/sns-auth` 브랜치) | [ ] |
| R1 | 스토어 심사 제출 (정책 URL은 web 완료 후 가능) | [ ] |

## 6. 공통 리스크 / 확인 필요 사항

| 항목 | 내용 | 대응 |
|------|------|------|
| 무음 촬영 | 한국·일본 단말은 셔터음 정책 존재. 이미지 스트림 프레임 캡처 방식은 가능하지만 몰래카메라 악용 우려로 심사 리젝 위험 | 설정에서 선택(기본 OFF), 스토어 설명에 용도 명시 |
| 레퍼런스 이미지 저작권 | 참고 이미지 4장은 타인 게시물 | 자체 촬영/구매 이미지로 교체 |
| AdMob 개인정보 | iOS ATT, EU UMP 동의 필요 | M1에서 UMP + ATT 흐름 포함 |
| 정책 URL | 스토어 등록에 개인정보처리방침 URL 필수 | web W1을 스토어 제출 전 완료 |
| 개인정보 (SNS 로그인) | 이메일·이름·제공자 식별자 수집 | 개인정보처리방침에 항목·보관 기간 명시, 앱 내 회원 탈퇴 제공 (Apple 5.1.1(v)) |
| Apple 4.8 | iOS에서 카카오/Google 로그인을 제공하면 Apple 로그인 필수 | iOS에 Apple 로그인 포함 (Android는 미제공) |
| 이메일 기반 계정 병합 | 카카오 이메일은 미인증일 수 있어 탈취 위험 | 제공자+고유 ID 단위로만 계정 식별, 이메일로 자동 병합하지 않음 |
