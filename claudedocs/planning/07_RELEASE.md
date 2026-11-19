# 07. 스토어 출시 진행 현황 (R1)

> 기준일: 2026-11-20 · 버전 1.0.0 · 등록 문구·라벨 원본: `mobile/store/listing.md`
> 출시 범위: 생성형 AI 사진 프리셋 2개(`full-body-low-angle`, `drink-cafe`)만 공개. `look-back`·`side-profile`은 관리자 콘솔에서 비공개, 앱·서버 내장 목록에서 제외

## 1. 식별 정보

| 항목 | 값 |
|---|---|
| Bundle ID / 패키지 | `com.woohalabs.likezzix` (변경 불가) |
| Apple 팀 | `KSSVSPN647` (Xcode 자동 서명) |
| App Store Connect 앱 ID | 6836852971 · 이름 "라익찍스 - 완벽 구도 카메라" · SKU `likezzix` |
| Play Console | 개발자 계정 woohaen88 (Chrome `u/2`) · 앱 ID 4974592127667640556 |
| Android 업로드 키 | `~/likezzix-upload-keystore.jks` + `mobile/android/key.properties` (git 제외, 별도 백업 필요) |
| Play 내부 테스트 참여 링크 | https://play.google.com/apps/internaltest/4700677291472981635 |

## 2. 빌드

| 플랫폼 | 버전 | 상태 |
|---|---|---|
| iOS | 1.0.0 (1) | TestFlight 업로드 (iPad 지원 포함 빌드, 사용 안 함) |
| iOS | 1.0.0 (2) | TestFlight 업로드 완료 (iPhone 전용, 암호화 미사용 선언). 처리 완료 후 버전 1.0에 연결 필요 |
| Android | 1 (1.0.0) | 내부 테스트 트랙 게시 완료, 기존 "테스터" 목록(37명) 연결 |

업로드 방법: iOS는 `flutter build ipa --release --dart-define-from-file=env/prod.json --export-options-plist=<destination upload 설정>` (Xcode 계정으로 바로 업로드, Flutter가 마지막에 IPA 폴더를 못 찾는 오류는 무시 · 성공 여부는 Xcode 배포 로그 `Upload succeeded`로 확인). Android AAB(약 100MB)는 Play Console에 직접 끌어다 놓기.

## 3. App Store Connect

- [x] Bundle ID 등록 (Certificates, Identifiers & Profiles)
- [x] 앱 레코드 생성 (한국어, SKU `likezzix`)
- [x] 스크린샷 3장 (1206x2622, `mobile/store/ios`)
- [x] 프로모션 텍스트·설명·키워드·지원 URL(`/support`)·저작권
- [x] 출시 방식: 수동 출시
- [x] 심사 정보: 로그인 불필요, 심사 메모, 연락처
- [x] 앱 정보: 이름·부제·카테고리(사진 및 비디오)
- [x] 콘텐츠 권리: 타사 콘텐츠 없음
- [x] 연령 등급 설문: 광고만 "예", 나머지 없음 → 4+
- [x] 가격 무료, 출시 국가 174개 (중국 본토 제외: AIGC 신고·보안 평가 서류 필요)
- [x] 개인정보처리방침 URL, 수집 데이터 6종 입력 (`listing.md` 표와 동일)
- [ ] 개인정보 응답 "게시" (입력만 완료, 게시 확인 대화상자에서 중단)
- [ ] 빌드 2 처리 완료 확인 후 버전 1.0에 연결
- [ ] 심사 제출 (제출 직전 사용자 확인)

## 4. Google Play Console

- [x] 앱 만들기 (한국어, 앱, 무료, 개발자 프로그램 정책·미국 수출법 선언 동의)
- [x] 내부 테스트 버전 1 (1.0.0) 게시, 출시 노트 입력
- [x] 테스터: 기존 "테스터" 이메일 목록 연결
- [ ] 스토어 등록정보: 간단한/자세한 설명, 아이콘(`icon_512.png`), 그래픽 이미지(`feature_graphic.png`), 휴대전화 스크린샷 3장 (`mobile/store/android`)
- [ ] 앱 콘텐츠: 개인정보처리방침 URL, 광고 포함, 앱 액세스(로그인 없음), 콘텐츠 등급 설문, 타겟층(만 18세 이상), 데이터 보안(`listing.md` 표)
- [ ] 프로덕션 출시 조건 확인 (개인 계정이면 비공개 테스트 12명 이상 14일)
- [ ] AdMob 앱을 스토어와 연결 → UMP 동의 메시지 게시 (`05_IMPROVEMENTS.md` 6번)

## 5. 저장소 반영 (머지 완료)

| PR | 내용 |
|---|---|
| #9 | 관리자 앱 미리보기 사진 가로 찌그러짐 수정 |
| #10 | 출시용 프리셋을 AI 사진 2개로 정리, 빈 카테고리 칩 숨김 |
| #11 | Android 릴리스 서명, iOS 개발팀 설정 |
| #12 | 스토어 스크린샷 integration test, 홍보 이미지 스크립트, `listing.md`, iPhone 전용, `/support` 페이지 |
| #13 | App Store 스크린샷 1206x2622로 변경 |

## 6. 주의

- 타인 인스타그램 원본 사진은 `claudedocs/images/instagram-reference-backup/`로 이동 (git 제외). 출시 빌드에 넣지 않음
- 스토어 스크린샷 재생성: `mobile/test_driver/screenshot_driver.dart` 주석의 `flutter drive` 명령(iPhone 17 Pro Max 시뮬레이터) → `uv run --with pillow python tool/store_assets.py`
