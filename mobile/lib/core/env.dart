/// `--dart-define-from-file=env/<환경>.json`으로 주입되는 빌드 환경값.
abstract final class Env {
  /// like-zzix API 서버 (예: https://like-zzix.woohalabs.com). 비우면 서버 호출 없음.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get hasApi => apiBaseUrl.isNotEmpty;
}
