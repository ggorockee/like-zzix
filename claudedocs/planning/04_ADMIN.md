# admin/ - 관리자 콘솔 설계

> 기준: Nuxt 4.6 (`ssr: false` SPA) + Nuxt UI 4.12 + `@mediapipe/tasks-vision` 1.2

## 1. 역할

관리자 콘솔의 핵심은 **프리셋(구도) 제작 도구**. 일반 CRUD보다 "레퍼런스 이미지 → 포즈 좌표 → 실루엣" 제작 흐름이 중요함.

| 기능 | 설명 |
|------|------|
| 로그인 | server 세션 쿠키 방식 (`/admin/v1/auth/login`) |
| 프리셋 목록 | 카테고리 필터, 공개 상태, 드래그 정렬 |
| 프리셋 편집기 | 이미지 업로드 → 브라우저에서 포즈 추출 → 관절 점 드래그 보정 → 실루엣 미리보기 → 권장 각도/비율/팁 입력 → 저장 |
| 실루엣 렌더링 | 편집기 Canvas에서 투명 PNG 실루엣과 썸네일(WebP)을 생성해 업로드 |
| 앱 미리보기 | 9:19.5 휴대폰 프레임 안에서 앱과 동일한 점선 스타일로 표시 |
| 카테고리 관리 | 이름, 정렬 |

광고 플래그는 Firebase Console에서 관리 (admin에 중복 구현하지 않음). 대시보드에 Firebase Console 바로가기 링크만 둠.

## 2. 왜 브라우저에서 포즈를 추출하는가

| 방식 | 판단 |
|------|------|
| admin 브라우저에서 MediaPipe Pose Landmarker | ✅ 채택. 모바일 ML Kit과 같은 BlazePose 33점 → 좌표 호환, 서버는 Go만 유지, 관리자가 결과를 보고 바로 수정 가능 |
| Go 서버에서 추출 | Go용 ML 런타임/모델 운영 부담 |
| 앱에서 매번 추출 | 가능하지만 프리셋마다 첫 로딩 지연, 잘못 추출돼도 보정 불가 → 폴백으로만 사용 |

## 3. 스택 / 폴더 구조

| 경로 | 내용 |
|------|------|
| `app/pages/login.vue` | 로그인 |
| `app/pages/presets/index.vue` | 목록 (`UTable`) |
| `app/pages/presets/[id].vue` | 편집기 |
| `app/pages/categories.vue` | 카테고리 |
| `app/components/pose/` | `PoseEditorCanvas`, `LandmarkHandle`, `SilhouettePreview`, `PhoneFramePreview` |
| `app/composables/` | `usePoseLandmarker` (모델 지연 로딩), `useApi` (`$fetch` + credentials), `useUpload` (presigned PUT) |
| `app/middleware/auth.global.ts` | 미로그인 시 `/login` 이동 |
| `nuxt.config.ts` | `ssr: false`, API Base URL 런타임 설정 |

배포: `nuxt generate` 결과물을 nginx 컨테이너로 K8s에 올리거나 CDN에 올리고, 접근은 IP 제한 또는 Cloudflare Access로 한 번 더 보호.

## 4. 작업 체크리스트

### A1. 기반
- [ ] Nuxt 4 SPA + Nuxt UI 대시보드 레이아웃
- [ ] 로그인 / 인증 미들웨어

### A2. 프리셋 관리
- [ ] 목록 / 상태 전환 / 정렬
- [ ] 카테고리 관리
- [ ] presigned 업로드

### A3. 포즈 편집기
- [ ] MediaPipe Pose Landmarker 연동 (33점 정규화 좌표)
- [ ] 관절 드래그 보정
- [ ] 실루엣 PNG / 썸네일 WebP 생성
- [ ] 휴대폰 프레임 미리보기
