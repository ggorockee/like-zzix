enum AuthFailure {
  /// 사용자가 SNS 로그인 창을 닫음 (메시지 표시 안 함)
  cancelled,

  /// SNS SDK 오류 또는 앱 키 미설정
  snsUnavailable,

  /// 서버가 자격 증명/토큰을 거부 (401)
  unauthorized,

  /// 요청 제한 초과 (429)
  tooManyAttempts,

  /// 서버 주소 미설정 빌드
  notConfigured,

  /// 네트워크/서버 오류
  network,
}

class AuthException implements Exception {
  const AuthException(this.failure, [this.detail]);

  final AuthFailure failure;
  final String? detail;

  String get message => switch (failure) {
    AuthFailure.cancelled => '로그인이 취소되었습니다.',
    AuthFailure.snsUnavailable => '지금은 이 방법으로 로그인할 수 없습니다.',
    AuthFailure.unauthorized => '로그인 정보가 만료되었습니다. 다시 로그인해 주세요.',
    AuthFailure.tooManyAttempts => '요청이 너무 많습니다. 잠시 후 다시 시도해 주세요.',
    AuthFailure.notConfigured => '서버 주소가 설정되지 않은 빌드입니다.',
    AuthFailure.network => '서버에 연결할 수 없습니다. 네트워크를 확인해 주세요.',
  };

  @override
  String toString() =>
      'AuthException($failure${detail == null ? '' : ': $detail'})';
}
