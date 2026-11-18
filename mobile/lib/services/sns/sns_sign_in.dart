import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/env.dart';
import '../../models/sns_credential.dart';
import '../../models/sns_provider.dart';
import '../auth_exception.dart';

/// SNS SDK 로그인. 결과 자격 증명은 서버로 보내 검증받는다 (앱은 신뢰하지 않음).
abstract interface class SnsSignIn {
  /// 현재 플랫폼/빌드에서 노출할 제공자 목록.
  List<SnsProvider> get availableProviders;

  /// 실패 시 [AuthException] (취소는 [AuthFailure.cancelled]).
  Future<SnsCredential> signIn(SnsProvider provider);

  /// SDK 로컬 로그인 상태 정리 (실패해도 무시).
  Future<void> signOut(SnsProvider provider);
}

class PlatformSnsSignIn implements SnsSignIn {
  Future<void>? _googleInit;

  @override
  List<SnsProvider> get availableProviders => [
    if (Env.kakaoNativeAppKey.isNotEmpty) SnsProvider.kakao,
    if (Env.googleServerClientId.isNotEmpty &&
        (!Platform.isIOS || Env.googleIosClientId.isNotEmpty))
      SnsProvider.google,
    // Android에서 Apple 로그인은 웹 플로우 + Service ID가 필요해 iOS에서만 제공.
    if (Platform.isIOS) SnsProvider.apple,
  ];

  @override
  Future<SnsCredential> signIn(SnsProvider provider) async {
    if (!availableProviders.contains(provider)) {
      throw const AuthException(AuthFailure.snsUnavailable, '미설정 제공자');
    }
    try {
      return switch (provider) {
        SnsProvider.kakao => await _kakao(),
        SnsProvider.google => await _google(),
        SnsProvider.apple => await _apple(),
      };
    } on AuthException {
      rethrow;
    } on GoogleSignInException catch (e) {
      throw AuthException(
        e.code == GoogleSignInExceptionCode.canceled
            ? AuthFailure.cancelled
            : AuthFailure.snsUnavailable,
        e.description,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      throw AuthException(
        e.code == AuthorizationErrorCode.canceled
            ? AuthFailure.cancelled
            : AuthFailure.snsUnavailable,
        e.message,
      );
    } on PlatformException catch (e) {
      throw AuthException(
        e.code == 'CANCELED'
            ? AuthFailure.cancelled
            : AuthFailure.snsUnavailable,
        '${e.code}: ${e.message}',
      );
    } on Object catch (e) {
      throw AuthException(AuthFailure.snsUnavailable, e.toString());
    }
  }

  @override
  Future<void> signOut(SnsProvider provider) async {
    try {
      switch (provider) {
        case SnsProvider.kakao:
          await UserApi.instance.logout();
        case SnsProvider.google:
          await _ensureGoogle();
          await GoogleSignIn.instance.signOut();
        case SnsProvider.apple:
          // Apple은 클라이언트 로그아웃 API가 없음 (탈퇴 시 서버가 토큰 revoke).
          break;
      }
    } on Object catch (e) {
      debugPrint('[SnsSignIn] ${provider.name} 로그아웃 무시: $e');
    }
  }

  Future<KakaoCredential> _kakao() async {
    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      try {
        token = await UserApi.instance.loginWithKakaoTalk();
      } on PlatformException catch (e) {
        // 사용자가 카카오톡 동의 화면에서 취소한 경우는 그대로 취소 처리.
        if (e.code == 'CANCELED') rethrow;
        // 카카오톡에 연결된 계정이 없으면 카카오계정(웹)으로 재시도.
        token = await UserApi.instance.loginWithKakaoAccount();
      }
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }
    return KakaoCredential(accessToken: token.accessToken);
  }

  Future<void> _ensureGoogle() =>
      _googleInit ??= GoogleSignIn.instance.initialize(
        clientId: Platform.isIOS ? Env.googleIosClientId : null,
        serverClientId: Env.googleServerClientId,
      );

  Future<GoogleCredential> _google() async {
    await _ensureGoogle();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(AuthFailure.snsUnavailable, 'ID 토큰 없음');
    }
    return GoogleCredential(idToken: idToken);
  }

  Future<AppleCredential> _apple() async {
    final rawNonce = _generateNonce();
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
    );
    final identityToken = credential.identityToken;
    if (identityToken == null) {
      throw const AuthException(AuthFailure.snsUnavailable, 'identity 토큰 없음');
    }
    final fullName = [
      credential.familyName,
      credential.givenName,
    ].whereType<String>().join(' ').trim();
    return AppleCredential(
      identityToken: identityToken,
      authorizationCode: credential.authorizationCode,
      rawNonce: rawNonce,
      fullName: fullName.isEmpty ? null : fullName,
    );
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
