# mobile/ - Flutter 앱 설계 (1순위)

> 기준: Flutter 3.47.9 / Dart 3.13.7 · Bundle ID `com.woohalabs.likezzix`
> 원본 요구사항: `claudedocs/PRD_MASTER.md` Step 1~5

## 1. 제품 범위 (MVP)

| 포함 | 제외 (차후) |
|------|-------------|
| 풀스크린 카메라 + 셔터/렌즈 전환/프리셋 썸네일 | 이메일/비밀번호 가입 |
| 구도 프리셋 Bottom Sheet (서버 + 번들 기본값) | 인앱 결제 (PRD상 영구 제외) |
| 레퍼런스 실루엣 오버레이 + 투명도 슬라이더 | 촬영 후 편집/필터 |
| 실시간 포즈 매칭 + 기울기 가이드 + Perfect Match 피드백 | 동영상 촬영 |
| 무음 촬영(선택), 비율 크롭(선택), 갤러리 저장 | 클라우드 백업 |
| 갤러리 사진 → 커스텀 실루엣 (보상형 광고 게이트) | 커스텀 실루엣 서버 공유 |
| Remote Config 기반 광고 3종 제어 | |
| SNS 로그인(선택) + `is_staff`/`is_superuser` 광고 면제 + 회원 탈퇴 (**마지막 단계**) | |

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
| `dio` | ^5.11.1 | 프리셋·인증 API 호출 |
| `flutter_secure_storage` | ^11.2.0 | 인증 토큰 보관 (Keychain / Keystore) |
| `kakao_flutter_sdk_user` | ^2.1.0 | 카카오 로그인 |
| `google_sign_in` | ^7.2.0 | Google 로그인 (ID 토큰) |
| `sign_in_with_apple` | ^8.2.0 | Apple 로그인 (iOS만) |
| `crypto` | 최신 | Apple nonce SHA-256 |
| `package_info_plus` | ^10.2.2 | 설정 화면 앱 버전 |
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
| `lib/services/` | `RemoteConfigService`, `AdService`, `AdConsentService`, `AuthApi`, `AuthSessionStore`, `sns/SnsSignIn`, `CameraService`, `PoseService`, `PoseMatcher`, `AttitudeService`, `CaptureService`, `PresetRepository`, `SettingsStore` |
| `lib/providers/` | 위 서비스를 노출하는 Riverpod Provider/Notifier |
| `lib/screens/` | `camera_screen.dart`, `settings_screen.dart` |
| `lib/widgets/` | `camera_preview_fullscreen`, `shutter_button`, `preset_bottom_sheet`, `preset_grid_item`, `native_ad_tile`, `silhouette_painter`, `attitude_indicator`, `opacity_slider`, `perfect_match_banner` |
| `assets/presets/` | 번들 기본 프리셋 JSON + 실루엣 PNG (오프라인 폴백) |
| `env/*.example.json` | `--dart-define-from-file` 템플릿 (API URL, 광고 단위 ID, Kakao/Google 키). 실제 `env/dev.json`, `env/prod.json`은 git 제외 |
| `ios/Flutter/App.xcconfig`, `Secrets.xcconfig` | AdMob App ID, Kakao 키, Google 역방향 클라이언트 ID (기본값은 App, 실제 값은 git 제외 Secrets) |
| `android/local.properties` | `admob.appId`, `kakao.nativeAppKey` (git 제외) |
| `test/` | 단위·위젯 테스트 |

## 4. 화면 및 UX

| 화면 | 구성 |
|------|------|
| CameraScreen (메인) | 전체 화면 프리뷰 / 상단: 투명도 슬라이더 + 단계별 촬영 가이드 카드(접기 가능), 우측 레퍼런스 사진 PiP(탭하면 크게) / 중앙: 레퍼런스 비율 프레임(모서리+3분할) + 사람 윤곽선 실루엣(글로우) + 자세계 / 하단: 각도 안내 문구, 프리셋 썸네일(좌), 셔터(중), 렌즈 전환(우) |
| PresetBottomSheet | 화면 50% 높이 Draggable Sheet, 카테고리 칩(전체/전신샷/부르고 찍기/옆모습/음료·카페), 칸에는 레퍼런스 사진(없으면 실루엣) + 3열 GridView, 첫 칸은 "내 사진으로 만들기" |
| SettingsScreen | 계정(로그인 / 이름·제공자·역할 배지 / 로그아웃 / 회원 탈퇴), 무음 촬영(기본 OFF), 비율 자동 크롭(기본 OFF), 격자선 표시, 개인정보처리방침/약관(web 링크), 오픈소스 라이선스, 앱 버전 |
| LoginScreen | "로그인은 선택 사항" 안내 + 카카오 / Google / Apple(iOS만) 버튼. 빌드에 키가 없는 제공자는 숨김 |
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
- 디버그 빌드는 항상 Google 테스트 광고 단위 ID 사용. 릴리스 빌드에서 광고 단위 ID가 비어 있으면 해당 광고는 로드하지 않음.
- 광고 SDK 초기화(UMP 동의 → iOS ATT → `MobileAds.initialize`)는 **첫 광고 요청 직전에 1회**. 플래그가 모두 false면 동의/ATT 팝업도 띄우지 않음.
- 실제 적용 플래그 = Remote Config 값 (M7 이후: 로그인 세션 복원 중이거나 광고 면제 계정이면 전부 false, 6.7).

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

### 6.7 계정 / 광고 면제 (마지막 단계, M7)

| 항목 | 내용 |
|------|------|
| 로그인 | 선택 사항. 설정 > 로그인에서 카카오 / Google / Apple(iOS). SDK가 준 자격 증명을 서버 `POST /v1/auth/{provider}`로 보내고 서버가 검증 |
| 자격 증명 | Google: ID 토큰 (`serverClientId`=웹 클라이언트 ID) / Kakao: access token / Apple: identity token + authorization code + raw nonce(+최초 이름) |
| 세션 저장 | access·refresh 토큰과 사용자 정보를 `flutter_secure_storage`에 보관 |
| 앱 시작 | 저장된 세션 즉시 복원 → 백그라운드로 `GET /v1/auth/me` 재검증. 401이면 refresh 후 1회 재시도, refresh도 401이면 로그아웃 처리. 네트워크 오류면 캐시 유지 |
| 역할 | `is_superuser` → superuser, `is_staff` → staff, 그 외 user, 비로그인 guest. JSON 값이 bool true가 아니면 권한 없음 |
| 광고 면제 | staff·superuser는 Remote Config와 무관하게 광고 3종 OFF, 광고 SDK·동의 팝업도 호출하지 않음. 역할이 바뀌면 `AdService`를 새로 만들고 미리 로드한 광고 폐기 |
| 로그아웃 | 로컬 세션 즉시 삭제 → 서버 refresh 폐기(실패 무시) → SDK 로그아웃 |
| 회원 탈퇴 | 확인 다이얼로그 → `DELETE /v1/auth/me` 성공 시에만 로컬 삭제 (실패하면 탈퇴된 것처럼 보이지 않게 유지) |

## 7. 오프라인 / 네트워크

- `PresetRepository`: 번들 프리셋 즉시 표시 → 백그라운드에서 `GET /v1/presets` (If-None-Match) → 성공 시 로컬 캐시 갱신.
- 서버가 준비되기 전에도 앱이 단독으로 동작해야 하므로 번들 프리셋 최소 8개 포함 (자체 제작 실루엣).

## 8. 품질 기준

| 항목 | 기준 |
|------|------|
| 정적 분석 | `flutter analyze` 경고 0 |
| 단위 테스트 | `PoseMatcher`(오차율·히스테리시스), `AttitudeService`(각도 계산), 광고 카운터, Remote Config 기본값, 광고 플래그 선검사, 역할별 광고 면제, 세션 복원·재검증·refresh·탈퇴 |
| 위젯 테스트 | 그리드 5번째 칸 광고/프리셋 분기, 슬라이더 연동, 로그인·로그아웃·탈퇴 흐름 |
| 실기기 검증 | iPhone 1대 + Android 중급기 1대에서 프리뷰 30fps 유지, 포즈 처리 ~10fps |

## 9. 작업 체크리스트

### M0. 프로젝트 초기화
- [x] `flutter create --org com.woohalabs --project-name likezzix` (iOS/Android만)
- [x] PRD 폴더 구조 생성 (`core`, `models`, `services`, `providers`, `screens`, `widgets`)
- [ ] Bundle ID `com.woohalabs.likezzix` 최종 확정
- [x] Firebase 프로젝트 생성 (`like-zzix`) + `flutterfire configure` (iOS/Android 앱 등록, `firebase_core` 추가)
- [ ] AdMob 앱 등록 및 App ID 발급 (사용자 계정 필요)
- [x] iOS 최소 버전 15.5 설정, Android minSdk는 Flutter 기본값 24 사용 (ML Kit 요구 21 이상 충족)
- [x] Firebase 설정 파일은 git 제외 (reviewmaps와 동일 정책), `Firebase.initializeApp()`은 네이티브 설정 파일 사용

### M1. 앱 초기화 + Remote Config + AdMob (PRD Step 1)
- [x] 패키지 추가 및 `main.dart` 초기화 순서 구성 (세로 고정 → Kakao → Firebase → Remote Config → ProviderScope)
- [x] `RemoteConfigService` + Provider, 기본값 4종 (실패 시 기본값으로 진행)
- [x] `AdService` (플래그 선검사, 테스트 ID 분기, 네이티브/전면/보상형 로드·표시)
- [x] UMP 동의 + iOS ATT 흐름 (첫 광고 요청 직전 지연 실행)
- [x] Info.plist / AndroidManifest 권한 문구 및 AdMob App ID (테스트 ID 기본, 실제 값은 git 제외 파일)
- [x] go_router 기본 라우트 (`/`), 라우터는 Provider로 앱마다 생성
- [ ] AdMob 실제 App ID / 광고 단위 ID 입력 (사용자 계정 필요)

### M2. 카메라 UI (PRD Step 2)
- [x] 풀스크린 프리뷰 + 라이프사이클 처리 (권한 팝업 중 초기화 경쟁 상태 수정, 카메라 열기 직렬화)
- [x] 셔터 / 렌즈 전환 / 프리셋 썸네일 버튼 (카메라 없는 기기 안내 화면)
- [x] 프리셋 Bottom Sheet + 카테고리 칩 + 3열 GridView
- [x] 5번째 칸 Native Ad 분기 (플래그 OFF·로드 실패 시 기본 프리셋)
- [x] 기본 프리셋 4개 = `claudedocs/images` 레퍼런스(전신샷/부르고 찍기/옆모습/음료 마시는 컷). MediaPipe Pose Landmarker(heavy)로 33점 + 사람 윤곽선을 미리 추출해 `presets.json`에 포함
- [x] 레퍼런스 사진은 `assets/presets/reference/`에 로컬 빌드 전용 (git 제외). 없으면 윤곽선 실루엣으로 대체
- [ ] 출시 전: 레퍼런스 사진을 자체 촬영/라이선스 확보 사진으로 교체 (ADR #6)
- [ ] 네이티브 광고 칸 레이아웃: 기본 템플릿은 그리드 칸에 맞지 않음 → 고도화 때 커스텀 `NativeAdFactory`
- [ ] 서버 `GET /v1/presets` 연동 + 로컬 캐시 (고도화)

### M3. 실루엣 오버레이 (PRD Step 3)
- [ ] `PoseService` (single / stream 모드)
- [ ] `PreviewTransform` 좌표 변환
- [x] `SilhouettePainter`: 윤곽선은 Catmull-Rom 곡선 + 글로우 + 옅은 채움, 캡션·테두리에 잘린 직선 구간 제외. 윤곽선 없는 프리셋은 관절 기반 볼륨 마네킹 + 투명도 슬라이더
- [x] 렌즈 전환 수정 (`setDescription`으로 렌즈만 교체)
- [ ] 투명도 값 저장 (고도화)
- [ ] 갤러리 사진 → 커스텀 실루엣 (보상형 광고 게이트)

### M4. 스마트 디렉팅 (PRD Step 4)
- [x] 가속도계 자세(pitch/roll, 저역 통과) + 중앙 자세계 + 목표 각도 안내 문구 + 일치 시 초록색·햅틱 (히스테리시스, 폰을 눕히면 세우라는 안내)
- [ ] `PoseMatcher` + 단위 테스트
- [ ] Perfect Match 피드백 (색상, 배너, 햅틱)

### M5. 촬영·저장·전면 광고 (PRD Step 5)
- [ ] 일반 촬영 / 무음 촬영 / 비율 크롭
- [x] 일반 촬영 → 갤러리 "LikeZZIX" 앨범 저장 + 저장 완료 스낵바 (Android 실기기 확인)
- [ ] 전면 광고 카운터 + 저장 완료 토스트
- [ ] 설정 화면

### M6. 출시 준비
- [ ] 앱 아이콘 / 스플래시
- [ ] Crashlytics / Analytics 이벤트 (`preset_selected`, `perfect_match`, `photo_saved`)
- [ ] 스토어 스크린샷, 개인정보처리방침 URL (web 의존)

### M7. 계정 / 광고 면제 (마지막 단계)
> 프로토타입 우선. 클라이언트 구현은 `feature/sns-auth` 브랜치에 보관 (테스트 포함), 프로토타입 완료 후 rebase하여 머지.

- [x] (브랜치) SNS 로그인 서비스 (카카오 / Google ID 토큰 / Apple nonce)
- [x] (브랜치) `AuthApi`, `AuthSessionStore`, `AuthController` (복원·재검증·refresh·로그아웃·탈퇴)
- [x] (브랜치) `is_staff` / `is_superuser` → 광고 3종 OFF, 세션 복원 중 광고 OFF
- [x] (브랜치) 로그인 화면, 설정 화면 계정 섹션, 회원 탈퇴
- [x] (브랜치) iOS URL 스킴·Apple 로그인 entitlement, Android 카카오 리다이렉트 Activity
- [ ] Kakao Developers 앱 등록, Google OAuth 클라이언트(iOS/Android/웹) 발급, Apple Sign in 활성화 (사용자 계정 필요)
- [ ] 서버 인증 API 연동 후 실기기 로그인 검증 (S1.5 의존)
