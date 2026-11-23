# 운영 가이드 — 모니터링·배포·버전 관리·광고

> 기준일: 2026-11-19 · 대전제: **모니터링되지 않는 것은 관리될 수 없다**
> 새 기능을 만들면 "어디서 보이는가(지표·대시보드)"와 "언제 알려주는가(알림)"를 함께 만든다.

## 1. 어디서 무엇을 보나

| 무엇 | 어디서 | 링크 / 위치 |
|------|--------|-------------|
| 서버 상태·API 지연·5xx | Grafana `라익찍스 (like-zzix)` | https://monitoring.ggorockee.com/d/like-zzix |
| 촬영 퍼널 (프리셋 선택 → Perfect Match → 저장) | 같은 대시보드 "촬영 퍼널" 행 | 프리셋별 전환율로 판정 기준 튜닝 |
| 앱 버전·플랫폼 분포, 업데이트 팝업 반응 | 같은 대시보드 "앱 사용 현황" 행 | 강제 업데이트 후 구버전 잔존 확인 |
| 관리자 콘솔·DB·프리셋 갱신·관리자 로그인 | 같은 대시보드 "관리자 콘솔 · DB" 행 | 콘솔: https://like-zzix-admin.woohalabs.com |
| 외부 접속 (도메인·인증서) | Grafana `cluster-overview` 서비스 접속 상태 | blackbox `like-zzix-api`, `like-zzix-admin` |
| 배포 상태 | ArgoCD 앱 `like-zzix` | https://argocd.ggorockee.com/applications/like-zzix |
| 앱 크래시 | Firebase Crashlytics (릴리스 빌드만) | Firebase 콘솔 > like-zzix > Crashlytics |
| 원격 설정 값·변경 이력 | Firebase Remote Config | 콘솔 버전 기록 + git `firebase/remoteconfig.template.json` |
| 광고 노출·수익 | AdMob 콘솔 | 실제 광고 단위 입력 후 |
| 서버 로그 | kubectl | `kubectl -n like-zzix logs deploy/like-zzix` (JSON, route·status·app_version 포함) |

## 2. 알림 (Alertmanager → woohaen88@gmail.com)

| 알림 | 조건 | 등급 | 먼저 볼 것 |
|------|------|------|-----------|
| LikeZzixServerDown | /metrics 수집 불가 5분 | CRITICAL | `kubectl -n like-zzix get pods`, ArgoCD 앱 상태 |
| LikeZzixHighErrorRate | 5xx 5% 초과 10분 | ERROR | 서버 로그 status≥500 |
| LikeZzixSlow | P95 1초 초과 15분 | WARN | CPU 쓰로틀링, 노드 부하 |
| LikeZzixEventsRejected | 이벤트 거부 30분 지속 | WARN | 앱 `AppEvent`와 서버 `AllowedEvents` 불일치 |
| LikeZzixPhotoSaveFailing | 1시간 저장 실패율 20% 초과 (5회 이상) | WARN | 앱 버전별 분포, Crashlytics |
| LikeZzixCameraUnavailableHigh | 1시간 카메라 불가 20% 초과 (실행 5회 이상) | WARN | 최근 앱 버전 배포 여부 |
| LikeZzixDatabaseDown | DB 연결 실패 5분 | ERROR | 서버 로그, Secret `like-zzix-credentials`, Cloud SQL 상태 (앱은 마지막 정상 프리셋으로 계속 동작) |
| LikeZzixCatalogStale | 프리셋 갱신 10분 넘게 실패 | WARN | `likezzix_catalog_refreshes_total{result="error"}`, 서버 로그 |
| LikeZzixAdminLoginDenied | 30분간 관리자 로그인 거부 10회 이상 | WARN | result 라벨 (허용 목록 밖 계정 / 토큰 오류 / 과도한 시도) |
| 공통 (클러스터) | 외부 접속 실패 3분, 인증서 만료, Pod 재시작·OOM, ArgoCD 실패 | 등급별 | infra `.claude/CLAUDE.md` 알림 표 |

대시보드 색상 기준과 알림 기준은 같은 값이다. 한쪽을 바꾸면 infra 저장소에서 다른 쪽도 함께 바꾼다 (`kube-prometheus-stack` valuefile `like-zzix-server` 그룹, `dashboards/like-zzix-dashboard.json`).

## 3. 서버 배포 흐름

| 단계 | 내용 |
|------|------|
| 1 | like-zzix 저장소 feature 브랜치 → PR → main 머지 (server/ 또는 앱 번들 프리셋 변경 시) |
| 2 | GitHub Actions `Server CI/CD`: gofmt·vet·staticcheck·race 테스트 → Docker Hub `ggorockee/like-zzix-server:<날짜>-<커밋>` |
| 3 | 같은 워크플로가 infra 저장소에 태그 변경 PR 생성·자동 머지 (`charts/helm/prod/like-zzix/values.yaml`) |
| 4 | ArgoCD가 자동 sync → Grafana "배포 버전" 패널에서 새 태그 확인 |
| 필요 시크릿 | like-zzix 저장소: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `INFRA_GITHUB_TOKEN` (2026-11-18 등록 완료) |

관리자 콘솔도 같은 방식이다: `admin/**` 변경이 main에 머지되면 `Admin CI/CD`가 lint·typecheck·test·generate → `ggorockee/like-zzix-admin` 이미지 → infra `admin.image.tag` PR 자동 머지.

| 무엇을 바꿨나 | 반영 경로 |
|------|------|
| `server/**`, 앱 번들 프리셋 | Server CI/CD → infra `image.tag` → ArgoCD 자동 배포 |
| `admin/**` | Admin CI/CD → infra `admin.image.tag` → ArgoCD 자동 배포 |
| `mobile/**` (앱 코드) | infra와 무관. 스토어 빌드·심사로 배포, 강제 업데이트는 Remote Config(4장) |
| `web/**` | 아직 배포 파이프라인 없음 (web 단계에서 추가) |
| 프리셋 내용 | 관리자 콘솔에서 편집·공개 → 서버가 30초 안에 반영 (배포 불필요) |

번들 프리셋(앱 오프라인·첫 실행용, 서버 시드용)을 바꿀 때는 `mobile/assets/presets/presets.json`을 고치고 `server/internal/presets/presets.json`에 같은 내용을 복사한다. 두 파일이 다르면 서버 테스트가 실패한다. 이미 DB에 프리셋이 있으면 시드는 다시 실행되지 않으므로 운영 프리셋은 콘솔에서 바꾼다.

### 관리자 콘솔 설정 (최초 1회)

| 항목 | 값 / 위치 |
|------|------|
| GSM `prod-like-zzix-credentials` (JSON) | POSTGRES_HOST(172.29.0.3)·PORT·USER·PASSWORD·DB(like_zzix), ADMIN_EMAILS(쉼표 구분), GOOGLE_CLIENT_ID. Terraform이 DB·사용자를 만들고 ESO가 Pod에 주입 |
| 관리자 추가·제거 | GSM 새 버전에서 ADMIN_EMAILS 수정 → ESO 갱신(최대 1시간) 후 `kubectl -n like-zzix rollout restart deploy/like-zzix`. 목록에서 빠진 관리자는 다음 요청부터 차단 |
| Google OAuth | yanggo-514212 웹 클라이언트(Grafana·ArgoCD와 공용)의 승인된 JavaScript 출처에 `https://like-zzix-admin.woohalabs.com` |

## 4. 앱 버전 관리 (Firebase Remote Config)

템플릿은 git `firebase/remoteconfig.template.json`이 원본이다. 콘솔에서 직접 바꾸면 다음 배포 때 덮어써지므로, 파일을 고친 뒤 `firebase` 폴더에서 Firebase CLI로 remoteconfig만 배포한다.

| 키 (플랫폼별) | 의미 | 기본값 |
|---------------|------|--------|
| `android_min_version`, `ios_min_version` | 현재 버전이 이보다 낮으면 **강제 업데이트** (닫을 수 없는 팝업, 스토어 이동만 가능) | 1.0.0 |
| `android_latest_version`, `ios_latest_version` | 이보다 낮으면 **선택 업데이트** (나중에 가능, 같은 버전은 1회만) | 1.0.0 |
| `android_store_url` | 비우면 패키지 이름으로 Play 스토어 링크 자동 생성 | 빈 값 |
| `ios_store_url` | App Store 등록 후 `https://apps.apple.com/app/id<번호>` 입력 (비우면 iOS 선택 업데이트 안내 안 함) | 빈 값 |
| `update_message` | 팝업 본문 (비우면 기본 문구) | 빈 값 |

| 출시 순서 | 할 일 | 확인 |
|-----------|-------|------|
| 1 | `pubspec.yaml` 버전 올려 스토어 심사 제출 | - |
| 2 | 심사 통과·출시 후 `*_latest_version`을 새 버전으로 → 배포 | 대시보드 "업데이트 안내 반응"에서 노출·클릭 |
| 3 | 치명적 버그 수정 등 구버전을 막아야 할 때만 `*_min_version` 올림 | "앱 버전별 요청"에서 구버전 감소 |
| 주의 | 스토어에 아직 없는 버전으로 min을 올리면 모든 사용자가 업데이트할 수 없는 팝업에 갇힌다 | 스토어 반영 확인 후 올림 |

검증 기록 (2026-11-18, Z Flip5): `android_latest_version`을 1.0.1로 임시 배포 → 앱 시작 시 "새 버전이 있어요" 팝업 → "업데이트" → Play 스토어 앱 열림 → 1.0.0으로 원복.

## 5. AdMob 설정

| 항목 | 상태 | 값 / 위치 |
|------|------|-----------|
| 퍼블리셔 | 기존 계정 사용 (돌려받엔과 동일) | `pub-8516861197467665` |
| app-ads.txt | 기존 `https://woohalabs.com/app-ads.txt` 사용 | 스토어 등록 시 개발자 웹사이트를 `woohalabs.com`으로 입력해야 인증됨 |
| 앱 등록 (Android / iOS) | [x] 2026-11-19 등록 | `라익찍스 Android`, `라익찍스 iOS` (스토어 미게시 → 상태 "검토 필요·광고 게재 제한됨", 출시 후 "스토어 추가"로 연결하면 해제) |
| 광고 단위 | [x] 플랫폼별 3개 | `preset_grid_native`(네이티브 고급형), `photo_saved_interstitial`(전면), `custom_silhouette_rewarded`(보상형, 기본 리워드 1 Reward) |
| App ID 입력 위치 | git 제외 파일 | Android `mobile/android/local.properties`의 `admob.appId`, iOS `mobile/ios/Flutter/Secrets.xcconfig`의 `ADMOB_APP_ID` |
| 광고 단위 ID 입력 위치 | git 제외 파일 | `mobile/env/prod.json` (`ADMOB_ANDROID_*`, `ADMOB_IOS_*`) |
| 노출 제어 | Remote Config `ads` 그룹 | 2026-11-24 네이티브(구도 목록)·전면(저장 3회마다, 잠금 중에는 미룸) ON, 보상형 OFF. 계정 woohalabs@gmail.com. 지표: `ad_native_shown`·`ad_interstitial_shown`·`ad_load_failed` |
| app-ads.txt | [x] 2026-11-24 | `woohalabs.com/app-ads.txt`(기존)와 `like-zzix.woohalabs.com/app-ads.txt`(서버 제공) |
| UMP 동의 메시지 | [ ] 스토어 연결 후 | 2026-11-19 시도: 새 유럽 규정 메시지에 두 앱과 개인정보처리방침 URL(`https://like-zzix.woohalabs.com/privacy`)을 지정했으나 게시·임시저장 버튼이 비활성 → 저장하지 않음. 기존 메시지는 스토어에 연결된 리뷰맵 앱만 대상이라 스토어 연결이 필요한 것으로 추정 (확인 필요). 출시 후 다시 생성·게시 |
| 실제 ID 반영 | [x] 2026-11-19 | Android `local.properties`, iOS `Secrets.xcconfig`, `env/prod.json`에 입력. 릴리스 빌드에서 Android 매니페스트·iOS Info.plist App ID와 광고 단위 6개 포함 확인 |

디버그 빌드는 항상 Google 테스트 광고를 쓴다. 실제 광고를 개발 기기에서 클릭하면 계정 정지 위험이 있으므로 AdMob 콘솔에 테스트 기기를 등록한다.

## 6. 앱 사용 이벤트 추가 방법

| 단계 | 파일 |
|------|------|
| 1. 서버 허용 목록에 추가 | `server/internal/telemetry/events.go` (`AllowedEvents`, 프리셋별이면 `PresetEvents`) |
| 2. 앱 열거형에 같은 이름 추가 | `mobile/lib/services/telemetry_service.dart` (`AppEvent`) |
| 3. 기록 지점에서 호출 | `ref.read(telemetryProvider)?.record(AppEvent.xxx, preset: id)` |
| 4. 대시보드·필요 시 알림 추가 | infra `dashboards/like-zzix-dashboard.json`, valuefile `like-zzix-server` 그룹 |
| 순서 | 서버를 먼저 배포한다. 앱이 먼저 나가면 새 이벤트가 거부되어 `LikeZzixEventsRejected` 알림이 울린다 |

이벤트에는 개인·기기 식별 정보를 넣지 않는다 (이름, 횟수, 프리셋 이름, 플랫폼, 앱 버전만).
