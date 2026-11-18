import 'package:flutter/foundation.dart';

import 'auth_user.dart';

/// 서버가 발급한 토큰 쌍 + 사용자 정보.
///
/// 서버 응답/로컬 저장 JSON:
/// `{"access_token":"...","refresh_token":"...","user":{...}}`
@immutable
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    accessToken: json['access_token'] as String,
    refreshToken: json['refresh_token'] as String,
    user: AuthUser.fromJson(json['user'] as Map<String, dynamic>),
  );

  final String accessToken;
  final String refreshToken;
  final AuthUser user;

  AuthSession copyWith({AuthUser? user}) => AuthSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    user: user ?? this.user,
  );

  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user': user.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.user == user;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, user);
}
