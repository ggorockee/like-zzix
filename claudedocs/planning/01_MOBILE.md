# mobile/ - Flutter 앱 설계 (1순위)

> 기준: Flutter 3.47.9 / Dart 3.13.7 · Bundle ID `com.woohalabs.likezzix`
> 원본 요구사항: `claudedocs/PRD_MASTER.md` Step 1~5

## 1. 제품 범위 (MVP)

| 포함 | 제외 (차후) |
|------|-------------|
| 풀스크린 카메라 + 셔터/렌즈 전환/프리셋 썸네일 | 회원가입·로그인 |
| 구도 프리셋 Bottom Sheet (서버 + 번들 기본값) | 인앱 결제 (PRD상 영구 제외) |
| 레퍼런스 실루엣 오버레이 + 투명도 슬라이더 | 촬영 후 편집/필터 |
| 실시간 포즈 매칭 + 기울기 가이드 + Perfect Match 피드백 | 동영상 촬영 |
| 무음 촬영(선택), 비율 크롭(선택), 갤러리 저장 | 클라우드 백업 |
| 갤러리 사진 → 커스텀 실루엣 (보상형 광고 게이트) | 커스텀 실루엣 서버 공유 |
| Remote Config 기반 광고 3종 제어 | |

## 2. 패키지 (2026-11-18 pub.dev 최신 기준)

| 패키지 | 버전 | 용도 |
|--------|------|------|
| `flutter_riverpod` | ^3.5.0 | 상태 관리 (단일 채택) |
| `go_router` | ^18.1.4 | 라우팅 + 딥링크 `/p/:presetId` |
| `camera` | ^0.12.2 | 프리뷰, 이미지 스트림, 촬영 |
| `google_mlkit_pose_detection` | ^1.0.3 | 온디바이스 33점 포즈 추출 |
| `sensors_plus` | ^7.1.1 | 가속도계 기반 pitch/roll |
| `google_mobile_ads` | ^9.2.0 | Native / Interstitial / Rewarded |
| `firebase_core`, `firebase_remote_config` | ^7.1.0 (RC) | 광고 플래그 |
| `firebase_crashlytics`, `firebase_analytics` | 최신 | 크래시·이벤트 수집 |
| `shared_preferences` | 최신 | 설정값, 광고 카운터 |
| `gal` | ^3.0.1 | 갤러리 저장 (iOS/Android 권한 처리 포함) |
| `image_picker` | 최신 | 갤러리 사진 선택 |
| `image` | 최신 | 무음 촬영 시 YUV/BGRA → JPEG 변환, 비율 크롭 |
| `dio` | 최신 | 프리셋 API 호출 (ETag) |
| `app_tracking_transparency` | 최신 | iOS ATT 동의 |
| `flutter_lints` / `very_good_analysis` | 최신 | 정적 분석 |

## 3. 폴더 구조

PRD 지정 4개 폴더(`screens`, `services`, `widgets`, `models`)를 유지하고 `providers`, `core`만 추가.

| 경로 | 내용 |
|------|------|
| `lib/main.dart` | 진입점: `WidgetsFlutterBinding` → Firebase/AdMob/RC 초기화 → `ProviderScope` |
| `lib/app.dart` | `MaterialApp.router`, 테마, go_router 설정 |
| `lib/core/` | 상수(`ad_unit_ids.dart`, `remote_config_keys.dart`), 테마, 환경값(`--dart-define-from-file`) |
| `lib/models/` | `Preset`, `PoseLandmarks`, `AttitudeState`, `MatchResult`, `AppSettings` |
| `lib/services/` | `RemoteConfigService`, `AdService`, `CameraService`, `PoseService`, `PoseMatcher`, `AttitudeService`, `CaptureService`, `PresetRepository`, `SettingsStore` |
| `lib/providers/` | 위 서비스를 노출하는 Riverpod Provider/Notifier |
| `lib/screens/` | `camera_screen.dart`, `settings_screen.dart` |
| `lib/widgets/` | `camera_preview_fullscreen`, `shutter_button`, `preset_bottom_sheet`, `preset_grid_item`, `native_ad_tile`, `silhouette_painter`, `attitude_indicator`, `opacity_slider`, `perfect_match_banner` |
| `assets/presets/` | 번들 기본 프리셋 JSON + 실루엣 PNG (오프라인 폴백) |
| `env/dev.json`, `env/prod.json` | API Base URL, 광고 단위 ID (prod 파일은 git 제외) |
| `test/` | 단위·위젯 테스트 |

## 4. 화면 및 UX

| 화면 | 구성 |
|------|------|
| CameraScreen (메인) | 전체 화면 프리뷰 / 상단: 투명도 슬라이더, 설정 아이콘, 비율 토글 / 중앙: 실루엣 오버레이 + 자세계 십자선 / 하단: 프리셋 썸네일(좌), 셔터(중), 렌즈 전환(우) |
| PresetBottomSheet | 화면 50% 높이 Draggable Sheet, 카테고리 탭(전신/상반신/부르고찍기/옆모습/소품) + 3열 GridView, 첫 칸은 "내 사진으로 만들기" |
| SettingsScreen | 무음 촬영(기본 OFF), 비율 자동 크롭(기본 OFF), 격자선 표시, 개인정보처리방침/약관(web 링크), 오픈소스 라이선스, 앱 버전 |
| 저장 완료 | SnackBar "저장 완료" + 썸네일 갱신 |

권한 요청 순서: 카메라(앱 첫 진입) → ATT(iOS, 첫 광고 로드 직전) → 사진 저장(첫 저장 시).

## 5. 데이터 모델

프리셋 JSON (서버 응답·번들 공통):

{"id":"full-body-low-angle","category":"full_body","title":"전신샷","tip":"살짝 밑에서 찍으면 훨씬 길어 보여요","thumbnail_url":"https://cdn.example.com/presets/full-body-low-angle/thumb.webp","silhouette_url":"https://cdn.example.com/presets/full-body-low-angle/silhouette.png","aspect_ratio":"3:4","camera":{"pitch_deg":-10,"roll_deg":0},"pose":{"format":"blazepose33","coord":"normalized","landmarks":[[0.51,0.22,0.98],[0.49,0.24,0.97]]},"sort_order":10,"updated_at":"2026-11-18T00:00:00Z"}

| 필드 | 설명 |
|------|------|
| `pose.landmarks` | 33개 `[x, y, likelihood]`, x·y는 프레임 기준 0~1 정규화 (index는 BlazePose 표준) |
| `camera.pitch_deg` | 권장 촬영 각도 (음수 = 아래에서 위로) |
| `aspect_ratio` | 비율 자동 크롭 시 사용 |
| `silhouette_url` | 서버에서 미리 렌더링한 실루엣 (없으면 landmarks로 앱에서 직접 그림) |

## 6. 핵심 로직 설계

### 6.1 Remote Config / 광고 (Step 1, 5)

| 키 | 기본값 | 사용처 |
|----|--------|--------|
| `show_native_ad` | false | 프리셋 그리드 5번째 칸 |
| `show_interstitial_ad` | false | 저장 N회마다 전면 광고 |
| `show_rewarded_ad` | false | 커스텀 실루엣 생성 게이트 |
| `interstitial_ad_interval` | 3 | 전면 광고 빈도 |

- `RemoteConfigService`: `setDefaults` → `fetchAndActivate`(timeout 10초, 실패해도 기본값으로 진행), `minimumFetchInterval` dev 0 / prod 1시간.
- `AdService`의 모든 public 메서드는 첫 줄에서 플래그를 확인하고 false면 즉시 반환 → 호출부에 분기 로직이 퍼지지 않게 함.
- 전면 광고 카운터: 저장 성공 시 +1 → `count >= interval && show_interstitial_ad`면 광고 표시 → 광고 닫힘 또는 미표시 시 0으로 초기화 (PRD Step 5 그대로). 카운트는 `shared_preferences`에 보존.
- 보상형 광고: `show_rewarded_ad=false`면 바로 실루엣 생성, true면 `onUserEarnedReward` 콜백 안에서만 생성 실행. 광고 로드 실패 시에는 생성 허용 (사용자 불이익 방지).
- 디버그 빌드는 항상 Google 테스트 광고 단위 ID 사용.

### 6.2 카메라 (Step 2)

- 프리뷰: `ResolutionPreset.high`, 화면 비율에 맞춰 `FittedBox(fit: cover)`로 꽉 채움. 화면에 잘려 보이는 영역과 실제 캡처 영역의 차이를 `PreviewTransform`(scale, offset, 회전, 전면 카메라 미러링)으로 한 곳에서 계산해 오버레이·매칭·크롭이 모두 같은 좌표 변환을 사용.
- 앱 라이프사이클: `inactive`에서 컨트롤러 dispose, `resumed`에서 재생성.

### 6.3 포즈 추출 및 실루엣 오버레이 (Step 3)

- 레퍼런스: 서버 프리셋은 `pose.landmarks`를 그대로 사용. 갤러리 사진은 `PoseDetectionMode.single`로 추출 후 이미지 크기로 정규화.
- 실시간: `startImageStream` → 처리 중인 프레임이 있으면 새 프레임 버림(최대 1개 in-flight) + 약 10fps로 제한 → `PoseDetectionMode.stream`. Android는 NV21, iOS는 BGRA8888 포맷으로 `InputImage` 생성.
- `SilhouettePainter`(CustomPaint): 관절 연결선(어깨-팔꿈치-손목, 어깨-엉덩이-무릎-발목, 어깨선, 골반선)과 머리 원을 흰색 점선으로 그림. 색상은 매칭 상태에 따라 흰색 → 초록색.
- 투명도 슬라이더: 0.1~1.0, 마지막 값을 설정에 저장.

### 6.4 포즈 매칭 알고리즘 (Step 4)

| 단계 | 내용 |
|------|------|
| 1. 비교 대상 | 코(0), 어깨(11,12), 팔꿈치(13,14), 손목(15,16), 엉덩이(23,24), 무릎(25,26), 발목(27,28) 총 13점 |
| 2. 좌표 통일 | 실시간 랜드마크를 `PreviewTransform`으로 화면 정규화 좌표(0~1)로 변환 — 레퍼런스와 같은 공간 |
| 3. 유효점 필터 | 양쪽 모두 likelihood ≥ 0.5인 점만 사용, 유효점이 8개 미만이면 "전신이 보이게 해주세요" 안내 |
| 4. 기준 길이 | 레퍼런스 몸통 길이 = 어깨 중점 ~ 엉덩이 중점 거리 (상반신 프리셋은 어깨 너비) |
| 5. 오차율 | 각 점 유클리드 거리 평균 ÷ 기준 길이 |
| 6. 기울기 | `|pitch - preset.pitch| ≤ 3°` 그리고 `|roll| ≤ 2°` |
| 7. 판정 | 오차율 < 0.10 + 기울기 일치가 300ms 지속되면 Perfect Match, 오차율 > 0.13이 되면 해제 (깜빡임 방지 히스테리시스) |
| 8. 피드백 | 진입 시 1회: 실루엣 초록색, "지금 찍으세요!" 배너, `HapticFeedback` 약 100ms |

위치·크기를 그대로 비교하므로 "구도(피사체의 화면 내 위치와 크기)"까지 맞춰야 일치 판정이 남. 이것이 일반 포즈 유사도와 다른 점.

### 6.5 자세계 (Step 4)

- 가속도계 값에 저역 통과 필터(alpha 0.1) 적용 후 세로 모드 기준 roll = atan2(ax, ay), pitch = atan2(az, √(ax²+ay²))로 계산.
- 중앙 십자선 + 수평선 막대: roll만큼 회전, pitch만큼 상하 이동. 목표 각도 범위 안이면 초록색.

### 6.6 촬영 및 저장 (Step 5)

| 모드 | 방식 |
|------|------|
| 일반 (기본) | 이미지 스트림 정지 → `takePicture()` → 스트림 재개 (일부 Android 기기는 스트림과 촬영 동시 사용 불가) |
| 무음 (설정 ON) | 가장 최근 스트림 프레임을 Isolate에서 JPEG로 변환 (해상도는 프리뷰 수준으로 낮아짐을 설정 화면에 안내) |
| 비율 크롭 (설정 ON) | 프리셋 `aspect_ratio`에 맞춰 중앙 기준 크롭 |

저장은 `gal`로 "LikeZZIX" 앨범에 저장 → 카운터/전면 광고 처리 → "저장 완료" 토스트.

## 7. 오프라인 / 네트워크

- `PresetRepository`: 번들 프리셋 즉시 표시 → 백그라운드에서 `GET /v1/presets` (If-None-Match) → 성공 시 로컬 캐시 갱신.
- 서버가 준비되기 전에도 앱이 단독으로 동작해야 하므로 번들 프리셋 최소 8개 포함 (자체 제작 실루엣).

## 8. 품질 기준

| 항목 | 기준 |
|------|------|
| 정적 분석 | `flutter analyze` 경고 0 |
| 단위 테스트 | `PoseMatcher`(오차율·히스테리시스), `AttitudeService`(각도 계산), 광고 카운터, Remote Config 기본값 |
| 위젯 테스트 | 그리드 5번째 칸 광고/프리셋 분기, 슬라이더 연동 |
| 실기기 검증 | iPhone 1대 + Android 중급기 1대에서 프리뷰 30fps 유지, 포즈 처리 ~10fps |

## 9. 작업 체크리스트

### M0. 프로젝트 초기화
- [x] `flutter create --org com.woohalabs --project-name likezzix` (iOS/Android만)
- [x] PRD 폴더 구조 생성 (`core`, `models`, `services`, `providers`, `screens`, `widgets`)
- [ ] Bundle ID `com.woohalabs.likezzix` 최종 확정
- [ ] Firebase 프로젝트 생성 + `flutterfire configure` (사용자 계정 필요)
- [ ] AdMob 앱 등록 및 App ID 발급 (사용자 계정 필요)
- [ ] iOS 최소 버전 15.5 이상, Android minSdk 21 이상 설정 (ML Kit 요구사항)

### M1. 앱 초기화 + Remote Config + AdMob (PRD Step 1)
- [ ] 패키지 추가 및 `main.dart` 초기화 순서 구성
- [ ] `RemoteConfigService` + Provider, 기본값 4종
- [ ] `AdService` (플래그 선검사, 테스트 ID 분기)
- [ ] UMP 동의 + iOS ATT 흐름
- [ ] Info.plist / AndroidManifest 권한 문구 및 AdMob App ID

### M2. 카메라 UI (PRD Step 2)
- [ ] 풀스크린 프리뷰 + 라이프사이클 처리
- [ ] 셔터 / 렌즈 전환 / 프리셋 썸네일 버튼
- [ ] 프리셋 Bottom Sheet + 카테고리 탭 + GridView
- [ ] 5번째 칸 Native Ad 분기
- [ ] 번들 기본 프리셋 + `PresetRepository`

### M3. 실루엣 오버레이 (PRD Step 3)
- [ ] `PoseService` (single / stream 모드)
- [ ] `PreviewTransform` 좌표 변환
- [ ] `SilhouettePainter` + 투명도 슬라이더
- [ ] 갤러리 사진 → 커스텀 실루엣 (보상형 광고 게이트)

### M4. 스마트 디렉팅 (PRD Step 4)
- [ ] `AttitudeService` + 자세계 위젯
- [ ] `PoseMatcher` + 단위 테스트
- [ ] Perfect Match 피드백 (색상, 배너, 햅틱)

### M5. 촬영·저장·전면 광고 (PRD Step 5)
- [ ] 일반 촬영 / 무음 촬영 / 비율 크롭
- [ ] 갤러리 저장 + 권한
- [ ] 전면 광고 카운터 + 저장 완료 토스트
- [ ] 설정 화면

### M6. 출시 준비
- [ ] 앱 아이콘 / 스플래시
- [ ] Crashlytics / Analytics 이벤트 (`preset_selected`, `perfect_match`, `photo_saved`)
- [ ] 스토어 스크린샷, 개인정보처리방침 URL (web 의존)
