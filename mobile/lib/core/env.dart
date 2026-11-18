/// `--dart-define-from-file=env/<환경>.json`으로 주입되는 빌드 환경값.
abstract final class Env {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Kakao Developers > 앱 키 > 네이티브 앱 키
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );

  /// Google Cloud OAuth 클라이언트 ID (iOS 유형)
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
  );

  /// Google Cloud OAuth 클라이언트 ID (웹 유형). 서버가 ID 토큰 audience로 검증.
  static const googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  static bool get hasApi => apiBaseUrl.isNotEmpty;
}
