import 'dart:async';

import 'package:likezzix/models/auth_session.dart';
import 'package:likezzix/models/auth_user.dart';
import 'package:likezzix/models/sns_credential.dart';
import 'package:likezzix/models/sns_provider.dart';
import 'package:likezzix/services/auth_api.dart';
import 'package:likezzix/services/auth_exception.dart';
import 'package:likezzix/services/auth_session_store.dart';
import 'package:likezzix/services/sns/sns_sign_in.dart';

class FakeAuthSessionStore implements AuthSessionStore {
  FakeAuthSessionStore([this.saved]);

  AuthSession? saved;

  @override
  Future<AuthSession?> read() async => saved;

  @override
  Future<void> write(AuthSession session) async => saved = session;

  @override
  Future<void> clear() async => saved = null;
}

class FakeSnsSignIn implements SnsSignIn {
  AuthException? error;
  final List<SnsProvider> signedOut = [];

  @override
  List<SnsProvider> get availableProviders => SnsProvider.values;

  @override
  Future<SnsCredential> signIn(SnsProvider provider) async {
    if (error != null) throw error!;
    return switch (provider) {
      SnsProvider.kakao => const KakaoCredential(accessToken: 'kakao'),
      SnsProvider.google => const GoogleCredential(idToken: 'google'),
      SnsProvider.apple => const AppleCredential(
        identityToken: 'apple',
        authorizationCode: 'code',
        rawNonce: 'nonce',
      ),
    };
  }

  @override
  Future<void> signOut(SnsProvider provider) async => signedOut.add(provider);
}

/// 서버 동작을 흉내내는 가짜 API. 토큰 유효성은 [validAccessTokens] 등으로 제어.
class FakeAuthApi implements AuthApi {
  AuthSession? signInResult;
  SnsCredential? lastCredential;

  /// `me` 응답. 미완료 상태로 두면 재검증이 대기한다.
  Completer<AuthUser> meResponse = Completer<AuthUser>();
  final Set<String> expiredAccessTokens = {};
  AuthSession? refreshResult;
  AuthFailure? refreshFailure;
  AuthFailure? deleteFailure;

  final List<String> loggedOut = [];
  final List<String> deletedWith = [];
  int refreshCalls = 0;

  @override
  Future<AuthSession> signIn(SnsCredential credential) async {
    lastCredential = credential;
    return signInResult!;
  }

  @override
  Future<AuthUser> me(String accessToken) {
    if (expiredAccessTokens.contains(accessToken)) {
      return Future.error(const AuthException(AuthFailure.unauthorized));
    }
    return meResponse.future;
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshCalls++;
    if (refreshFailure != null) throw AuthException(refreshFailure!);
    return refreshResult!;
  }

  @override
  Future<void> logout(String refreshToken) async {
    loggedOut.add(refreshToken);
    throw const AuthException(AuthFailure.network);
  }

  @override
  Future<void> deleteAccount(String accessToken) async {
    if (expiredAccessTokens.contains(accessToken)) {
      throw const AuthException(AuthFailure.unauthorized);
    }
    if (deleteFailure != null) throw AuthException(deleteFailure!);
    deletedWith.add(accessToken);
  }
}

AuthUser user({
  bool isStaff = false,
  bool isSuperuser = false,
  SnsProvider provider = SnsProvider.kakao,
  String name = '테스터',
}) => AuthUser(
  id: '1',
  provider: provider,
  name: name,
  isStaff: isStaff,
  isSuperuser: isSuperuser,
);

AuthSession session({
  String access = 'a1',
  String refresh = 'r1',
  AuthUser? owner,
}) => AuthSession(
  accessToken: access,
  refreshToken: refresh,
  user: owner ?? user(),
);
