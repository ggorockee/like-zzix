import 'package:dio/dio.dart';

import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../models/sns_credential.dart';
import 'auth_exception.dart';

/// Go 서버 인증 API 클라이언트 (`02_SERVER.md` 5장).
///
/// | Method | Path | 설명 |
/// |---|---|---|
/// | POST | `/v1/auth/{kakao,google,apple}` | SNS 자격 증명 → 토큰 쌍 + 사용자 |
/// | POST | `/v1/auth/refresh` | refresh 토큰 회전 |
/// | POST | `/v1/auth/logout` | refresh 토큰 폐기 |
/// | GET | `/v1/auth/me` | 사용자 정보 (is_staff / is_superuser 포함) |
/// | DELETE | `/v1/auth/me` | 회원 탈퇴 |
class AuthApi {
  AuthApi(this._dio);

  final Dio? _dio;

  Future<AuthSession> signIn(SnsCredential credential) => _call(() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/v1/auth/${credential.provider.name}',
      data: credential.toJson(),
    );
    return AuthSession.fromJson(res.data!);
  });

  Future<AuthSession> refresh(String refreshToken) => _call(() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return AuthSession.fromJson(res.data!);
  });

  Future<AuthUser> me(String accessToken) => _call(() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/v1/auth/me',
      options: _bearer(accessToken),
    );
    return AuthUser.fromJson(res.data!);
  });

  Future<void> logout(String refreshToken) => _call(
    () => _client.post<void>(
      '/v1/auth/logout',
      data: {'refresh_token': refreshToken},
    ),
  );

  Future<void> deleteAccount(String accessToken) => _call(
    () => _client.delete<void>('/v1/auth/me', options: _bearer(accessToken)),
  );

  Dio get _client =>
      _dio ?? (throw const AuthException(AuthFailure.notConfigured));

  Options _bearer(String token) =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      throw AuthException(switch (error.response?.statusCode) {
        401 => AuthFailure.unauthorized,
        429 => AuthFailure.tooManyAttempts,
        _ => AuthFailure.network,
      }, error.message);
    } on AuthException {
      rethrow;
    } on Object catch (error) {
      throw AuthException(AuthFailure.network, error.toString());
    }
  }
}
