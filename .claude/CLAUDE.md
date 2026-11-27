# like-zzix

## 업데이트 안내 카드 (다음 버전부터 적용)

2026-11-27 결정: 앞으로 업데이트는 화면 대부분을 덮는 넘김 카드로 알립니다. 세 앱 공통 표준은 infra 저장소 `claudedocs/app-update-card.md`, 기준 구현은 reviewmaps `mobile/`(2.2.3)입니다. 아직 적용 전이며 지금은 `mobile/lib/widgets/update_dialog.dart`의 작은 팝업을 씁니다.

| 순서 | 다음 앱 버전에서 할 일 |
|------|------------------------|
| 1 | 신규 설치 구분 방법 결정: 지금은 첫 실행에 저장하는 값이 없음 (설치·갱신 시각 비교, 또는 이번 버전에서 표시를 저장하고 그다음 버전부터 보여주기) |
| 2 | `release_note` 모델·서비스·카드 화면 이식, `mobile/assets/release_notes.json` 추가(1~3장), 버전 일치 테스트 |
| 3 | `UpdatePrompt`가 팝업 대신 카드를 띄우게 변경. 강제·선택 규칙(버전당 1회)과 스플래시에서 강제 업데이트를 막는 동작은 유지 |
| 4 | `firebase/remoteconfig.template.json`과 `remote_config_keys.dart`에 `release_note` 키 추가 |
| 5 | 이벤트(카드 표시, 선택, 본 장)를 앱과 서버 허용 목록에 함께 추가 (빠지면 `LikeZzixEventsRejected` 알림) |
| 6 | 이전 버전 위에 덮어 설치해 카드 1회 표시, 새 설치에는 없는지 확인 |

적용한 뒤에는 릴리스마다 `release_notes.json`을 갱신합니다.
