# web/ - 공개 웹사이트 설계

> 기준: Nuxt 4.6 (SSG, `nuxt generate`) + Nuxt UI 4 · Node 서버 없이 정적 배포

## 1. 역할

웹은 앱의 보조 채널. 기능을 웹에 다시 만들지 않음.

| 페이지 | 목적 | 우선순위 |
|--------|------|----------|
| `/` 랜딩 | 앱 소개, 데모 GIF, 스토어 버튼 (ASO 보조, SEO) | 높음 |
| `/privacy` 개인정보처리방침 | **스토어 등록 필수 URL** (AdMob, Firebase 수집 항목 명시) | 최우선 |
| `/terms` 이용약관 | 스토어·광고 정책 대응 | 최우선 |
| `/p/[id]` 프리셋 공유 | 앱 설치 시 딥링크로 앱 열기, 미설치 시 스토어 이동 + OG 이미지 | 중간 |
| `/.well-known/apple-app-site-association`, `/.well-known/assetlinks.json` | iOS Universal Links / Android App Links | 중간 |
| `/app-ads.txt` | AdMob 앱 광고 인증 파일 | 높음 |

## 2. 스택 선택 이유

| 항목 | 내용 |
|------|------|
| Nuxt 4 SSG | 모든 페이지를 빌드 시 HTML로 생성 → SEO 확보, 서버 없이 CDN 배포 |
| `/p/[id]` | 빌드 시 서버 `/v1/presets`를 조회해 공개 프리셋 페이지를 미리 생성 (프리셋이 바뀌면 재빌드) |
| Nuxt UI 4 | admin과 동일 컴포넌트 → 디자인 일관성 |
| `@nuxtjs/i18n` | 한국어 기본, 영어는 차후 |
| 배포 | Cloudflare Pages / S3+CloudFront / K8s nginx 중 택1 |

## 3. 폴더 구조

| 경로 | 내용 |
|------|------|
| `app/pages/` | `index.vue`, `privacy.vue`, `terms.vue`, `p/[id].vue` |
| `app/components/` | `HeroSection`, `FeatureGrid`, `StoreBadges`, `SiteFooter` |
| `content/` | 정책 문서 (`@nuxt/content` 마크다운) |
| `public/` | `app-ads.txt`, `.well-known/*`, 파비콘, OG 기본 이미지 |
| `nuxt.config.ts` | `nitro.prerender.routes`에 프리셋 경로 주입 |

## 4. 작업 체크리스트

### W1. 출시 필수
- [ ] Nuxt 4 프로젝트 생성 + Nuxt UI
- [ ] `/privacy`, `/terms` (AdMob·Firebase·카메라·사진 권한 사용 목적 명시)
- [ ] `/app-ads.txt`
- [ ] 랜딩 페이지 + 스토어 배지
- [ ] 도메인 연결 및 정적 배포

### W2. 공유/딥링크
- [ ] `/p/[id]` 프리렌더 + OG 메타
- [ ] Universal Links / App Links 파일
- [ ] mobile `go_router` 딥링크 연동 확인
