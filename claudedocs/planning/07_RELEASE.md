# 07. 스토어 출시 진행 현황 (R1)

> 기준일: 2026-11-24 · 버전 1.0.0 · 등록 문구·라벨 원본: `mobile/store/listing.md` · 제출 이후 할 일: `10_POST_SUBMISSION.md`
> 출시 범위: 구도 23종, AI 예시 사진 12장(`cmp-*`). 이전 프리셋 4개(`full-body-low-angle`, `drink-cafe`, `look-back`, `side-profile`)는 관리자 콘솔에서 비공개(완전 삭제는 결정 대기)

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
| iOS | 1.0.0 (2) | TestFlight 업로드 (이전 화면, 사용 안 함) |
| iOS | 1.0.0 (3) | 2026-11-24 업로드 완료(`main` d8d0d3f). 경고는 2027년 4월부터 iOS 27 SDK 필요, 광고·ML Kit dSYM 없음(제출에는 영향 없음). 구도를 고르면 종료되는 문제가 있어 사용 안 함 |
| iOS | 1.0.0 (4) | 2026-11-25 업로드. 빌드 3에서 구도를 고르면 앱이 종료되던 문제 수정 (ML Kit 링커 플래그·모델 번들 누락). 2026-11-25 22:30 재제출 후 빌드 5로 바꾸려고 취소 |
| iOS | 1.0.0 (5) | 2026-11-25 23:07 업로드(`main` 92f772a + 빌드 번호). 저장 알림 위치, 촬영 중 잘못된 초록불, 안내 문구·그림. **23:14 재제출, 심사 대기**. TestFlight `Internal` 그룹 연결. 실기기 확인 전 |
| Android | 1 (1.0.0) | 내부 테스트 트랙 게시 완료, 기존 "테스터" 목록(37명) 연결 (이전 화면) |
| Android | 3 (1.0.0) | 2026-11-24 비공개 테스트(Alpha)에 업로드·저장(신규 설치 36.1MB), 게시됨. 릴리스 코드에 WorkDatabase 생성자가 빠져 **실행 직후 종료되는 빌드**(dex에서 확인) |
| Android | 5 (1.0.0) | 2026-11-25 Alpha 업로드. 실기기(Z Flip5)에서 실행 직후 종료 확인, **사용 금지** |
| Android | 6 (1.0.0) | 2026-11-25 빌드. R8 보존 규칙(`android/app/proguard-rules.pro`) 추가, 실기기에서 실행·촬영·렌즈·배율·재실행 종료 0건. 검토 제출(버전 5를 대체) |

업로드 방법: iOS는 `flutter build ipa --release --dart-define-from-file=env/prod.json --export-options-plist=<destination upload 설정>` (Xcode 계정으로 바로 업로드, Flutter가 마지막에 IPA 폴더를 못 찾는 오류는 무시 · 성공 여부는 Xcode 배포 로그 `Upload succeeded`로 확인). Android AAB(약 100MB)는 Play Console에 직접 끌어다 놓기.

## 3. App Store Connect

- [x] Bundle ID 등록 (Certificates, Identifiers & Profiles)
- [x] 앱 레코드 생성 (한국어, SKU `likezzix`)
- [x] 스크린샷 4장 교체 (1206x2622, `mobile/store/ios`, 이전 3장 제거)
- [x] 프로모션 텍스트·설명·키워드·심사 메모를 `listing.md` 최신 문구로 교체, 마케팅 URL 추가
- [x] 출시 방식: 수동 출시
- [x] 심사 정보: 로그인 불필요, 연락처
- [x] 앱 정보: 이름·부제·카테고리(사진 및 비디오)
- [x] 콘텐츠 권리: 타사 콘텐츠 없음
- [x] 연령 등급 설문: 광고만 "예", 나머지 없음 → 4+
- [x] 연령 등급 새 질문 (위치 공유·데이팅 모두 아니요, 4+ 유지)
- [x] 가격 무료, 출시 국가 174개 (중국 본토 제외: AIGC 신고·보안 평가 서류 필요)
- [x] 개인정보처리방침 URL, 수집 데이터 6종 입력 (`listing.md` 표와 동일)
- [x] 개인정보 응답 "게시" (2026-11-24)
- [x] 개인정보 응답 보완·재게시 7종 (AdMob iOS 공식 문서 기준: 제품 상호작용·충돌·기타 진단 목적 추가, 성능 데이터 추가)
- [ ] 개인정보처리방침 4항 AdMob 항목에 광고 상호작용·진단·성능 정보와 사기 예방 목적 추가
- [x] 빌드 3 처리 완료 확인 후 버전 1.0에 연결
- [ ] 실제 iPhone에서 TestFlight 빌드 3 확인 (제출은 먼저 진행, 수동 출시 버튼을 누르기 전에 확인)
- [x] 심사 제출 (2026-11-24, Waiting for Review, 최대 48시간, 승인 후 수동 출시)

## 4. Google Play Console

- [x] 앱 만들기 (한국어, 앱, 무료, 개발자 프로그램 정책·미국 수출법 선언 동의)
- [x] 내부 테스트 버전 1 (1.0.0) 게시, 출시 노트 입력
- [x] 테스터: 기존 "테스터" 이메일 목록 연결
- [x] 스토어 등록정보: 카테고리(사진)·공개 연락처, 간단한/자세한 설명, 아이콘(`icon_512.png`), 그래픽 이미지(`feature_graphic.png`), 휴대전화 스크린샷 4장 (`mobile/store/android`), 스크린샷 4장 AI 생성 라벨 지정
- [x] 앱 콘텐츠 선언 10종 저장: 개인정보처리방침 URL, 광고 포함, 앱 액세스(로그인 없음), 콘텐츠 등급 설문, 타겟층(만 18세 이상), 데이터 보안(`listing.md` 표), 광고 ID, 정부·금융·건강 앱 아님. 콘텐츠 등급은 서버에서 받는 예시 사진 때문에 온라인 콘텐츠 "예", 결과 전체이용가
- [x] 프로덕션 출시 조건 확인: 개인 계정이라 비공개 테스트 12명 이상 14일 후 액세스 신청 필요
- [x] 비공개 테스트(Alpha) 테스터 목록 "테스터"(57명)·국가 146개 설정 (유럽 EEA·영국·스위스 32개는 UMP 동의 메시지 게시 후 추가)
- [x] 비공개 테스트 트랙에 버전 3 업로드·저장 (게시 개요에 변경사항 14개)
- [x] 게시 개요 경고 `android.hardware.screen.portrait` 무시 처리 (사유: 해결 계획 있음)
- [ ] 다음 빌드에서 세로 화면 기능을 `required=false`로 선언 (대화면 대응과 함께, `10_POST_SUBMISSION.md` 5장)
- [x] 검토 전송 (2026-11-24, 사용자가 직접 제출)
- [ ] AdMob 앱을 스토어와 연결 → UMP 동의 메시지 게시 (`05_IMPROVEMENTS.md` 6번)

## 5. 저장소 반영 (머지 완료)

| PR | 내용 |
|---|---|
| #9 | 관리자 앱 미리보기 사진 가로 찌그러짐 수정 |
| #10 | 출시용 프리셋을 AI 사진 2개로 정리, 빈 카테고리 칩 숨김 |
| #11 | Android 릴리스 서명, iOS 개발팀 설정 |
| #12 | 스토어 스크린샷 integration test, 홍보 이미지 스크립트, `listing.md`, iPhone 전용, `/support` 페이지 |
| #13 | App Store 스크린샷 1206x2622로 변경 |
| #15~#19 | 브랜드, 움직이는 가이드, 인물 코칭, 구도 23종과 예시 사진 12장 |
| #20 | 1.0.0 출시 준비: 광고, 정보 화면, 권한 정리, 저장 해상도, 흐린 실루엣, app-ads.txt·정책 페이지 (운영 반영 확인) |

## 6. 주의

- 타인 인스타그램 원본 사진은 `claudedocs/images/instagram-reference-backup/`로 이동 (git 제외). 출시 빌드에 넣지 않음
- 스토어 스크린샷 재생성: `mobile/test_driver/screenshot_driver.dart` 주석의 `flutter drive` 명령(iPhone 17 Pro Max 시뮬레이터) → `uv run --with pillow python tool/store_assets.py`
