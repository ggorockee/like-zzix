import 'sns_provider.dart';

/// SNS SDK에서 받은 자격 증명. 서버가 제공자별로 검증한 뒤 자체 토큰을 발급.
sealed class SnsCredential {
  const SnsCredential();

  SnsProvider get provider;

  /// `POST /v1/auth/{provider}` 요청 본문
  Map<String, String> toJson();
}

/// 서버 검증: Google 공개키로 서명 + `aud`가 웹 클라이언트 ID인지 확인.
final class GoogleCredential extends SnsCredential {
  const GoogleCredential({required this.idToken});

  final String idToken;

  @override
  SnsProvider get provider => SnsProvider.google;

  @override
  Map<String, String> toJson() => {'id_token': idToken};
}

/// 서버 검증: `access_token_info`의 `app_id`가 우리 앱인지 확인 후 사용자 조회.
final class KakaoCredential extends SnsCredential {
  const KakaoCredential({required this.accessToken});

  final String accessToken;

  @override
  SnsProvider get provider => SnsProvider.kakao;

  @override
  Map<String, String> toJson() => {'access_token': accessToken};
}

/// 서버 검증: Apple 공개키 서명, `aud`=번들 ID, `nonce`=sha256(rawNonce).
/// `authorizationCode`는 회원 탈퇴 시 Apple 토큰 폐기(revoke)에 사용.
final class AppleCredential extends SnsCredential {
  const AppleCredential({
    required this.identityToken,
    required this.authorizationCode,
    required this.rawNonce,
    this.fullName,
  });

  final String identityToken;
  final String authorizationCode;
  final String rawNonce;

  /// Apple은 이름을 최초 로그인 때만 제공하므로 함께 전달.
  final String? fullName;

  @override
  SnsProvider get provider => SnsProvider.apple;

  @override
  Map<String, String> toJson() => {
    'identity_token': identityToken,
    'authorization_code': authorizationCode,
    'nonce': rawNonce,
    if (fullName != null && fullName!.isNotEmpty) 'full_name': fullName!,
  };
}
