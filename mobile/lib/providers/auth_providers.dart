import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account_role.dart';
import '../models/auth_session.dart';
import '../models/sns_provider.dart';
import '../services/auth_api.dart';
import '../services/auth_exception.dart';
import '../services/auth_session_store.dart';
import '../services/sns/sns_sign_in.dart';
import 'api_providers.dart';

final authSessionStoreProvider = Provider<AuthSessionStore>(
  (ref) => AuthSessionStore(),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => AuthApi(ref.watch(dioProvider)),
);

final snsSignInProvider = Provider<SnsSignIn>((ref) => PlatformSnsSignIn());

/// 로그인 세션. 로그인하지 않은 사용자는 null (로그인은 선택 사항).
///
/// 앱 시작 시 보안 저장소의 세션을 즉시 복원하고, 백그라운드에서 서버로 재검증해
/// 관리자 콘솔에서 바뀐 역할(is_staff / is_superuser)을 반영한다.
/// - access 만료(401): refresh로 갱신 후 재시도
/// - refresh도 거부(401): 세션 삭제 → 비로그인
/// - 네트워크 오류: 캐시된 세션 유지 (오프라인 촬영 지원)
final authSessionProvider = AsyncNotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthSession?> {
  AuthSessionStore get _store => ref.read(authSessionStoreProvider);
  AuthApi get _api => ref.read(authApiProvider);
  SnsSignIn get _sns => ref.read(snsSignInProvider);

  @override
  Future<AuthSession?> build() async {
    final cached = await _store.read();
    if (cached != null) unawaited(_revalidate(cached));
    return cached;
  }

  /// SNS 로그인 → 서버 토큰 발급. 실패 시 [AuthException].
  Future<void> signIn(SnsProvider provider) async {
    final credential = await _sns.signIn(provider);
    final session = await _api.signIn(credential);
    await _save(session);
  }

  /// 로그아웃. 서버 토큰 폐기에 실패해도 로컬 세션은 반드시 삭제.
  Future<void> signOut() async {
    final session = state.value;
    await _clear();
    if (session == null) return;
    try {
      await _api.logout(session.refreshToken);
    } on AuthException catch (e) {
      debugPrint('[Auth] 서버 로그아웃 실패(로컬 삭제 완료): $e');
    }
    final provider = session.user.provider;
    if (provider != null) await _sns.signOut(provider);
  }

  /// 회원 탈퇴. 서버 삭제가 성공한 경우에만 로컬 세션을 지운다.
  Future<void> deleteAccount() async {
    final session = state.value;
    if (session == null) return;
    await _withFreshSession(session, (s) => _api.deleteAccount(s.accessToken));
    await _clear();
    final provider = session.user.provider;
    if (provider != null) await _sns.signOut(provider);
  }

  Future<void> _revalidate(AuthSession cached) async {
    try {
      final user = await _withFreshSession(
        cached,
        (s) => _api.me(s.accessToken),
      );
      final current = state.value;
      if (!ref.mounted || current == null) return;
      if (current.user != user) await _save(current.copyWith(user: user));
    } on AuthException catch (e) {
      if (!ref.mounted) return;
      if (e.failure == AuthFailure.unauthorized &&
          state.value?.refreshToken == cached.refreshToken) {
        await _clear();
      }
    }
  }

  /// access 토큰으로 요청하고 401이면 refresh 후 한 번 재시도.
  /// refresh도 401이면 [AuthFailure.unauthorized]를 그대로 던진다.
  Future<T> _withFreshSession<T>(
    AuthSession session,
    Future<T> Function(AuthSession session) request,
  ) async {
    try {
      return await request(session);
    } on AuthException catch (e) {
      if (e.failure != AuthFailure.unauthorized) rethrow;
    }
    final refreshed = await _api.refresh(session.refreshToken);
    if (ref.mounted && state.value?.refreshToken == session.refreshToken) {
      await _save(refreshed);
    }
    return request(refreshed);
  }

  Future<void> _save(AuthSession session) async {
    await _store.write(session);
    state = AsyncData(session);
  }

  Future<void> _clear() async {
    await _store.clear();
    state = const AsyncData(null);
  }
}

/// 현재 사용자 역할. 비로그인이면 [AccountRole.guest].
final accountRoleProvider = Provider<AccountRole>(
  (ref) => ref.watch(authSessionProvider).value?.user.role ?? AccountRole.guest,
);

/// 광고 면제 여부 (is_staff 또는 is_superuser).
final isAdFreeProvider = Provider<bool>(
  (ref) => ref.watch(accountRoleProvider).isAdFree,
);
