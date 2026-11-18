import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/account_role.dart';
import 'package:likezzix/models/ad_flags.dart';
import 'package:likezzix/models/sns_credential.dart';
import 'package:likezzix/models/sns_provider.dart';
import 'package:likezzix/providers/ad_providers.dart';
import 'package:likezzix/providers/auth_providers.dart';
import 'package:likezzix/services/auth_exception.dart';

import '../fakes/auth_fakes.dart';

const _allOn = AdFlags(
  showNativeAd: true,
  showInterstitialAd: true,
  showRewardedAd: true,
  interstitialAdInterval: 3,
);

void main() {
  late FakeAuthSessionStore store;
  late FakeAuthApi api;
  late FakeSnsSignIn sns;

  ProviderContainer createContainer() {
    final container = ProviderContainer(
      overrides: [
        remoteAdFlagsProvider.overrideWithValue(_allOn),
        authSessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(api),
        snsSignInProvider.overrideWithValue(sns),
      ],
    );
    addTearDown(container.dispose);
    container.listen(adFlagsProvider, (_, _) {});
    return container;
  }

  Future<ProviderContainer> restored() async {
    final container = createContainer();
    await container.read(authSessionProvider.future);
    return container;
  }

  setUp(() {
    store = FakeAuthSessionStore();
    api = FakeAuthApi();
    sns = FakeSnsSignIn();
  });

  group('역할별 광고 적용', () {
    test('비로그인: Remote Config 플래그 그대로', () async {
      final container = await restored();
      expect(container.read(accountRoleProvider), AccountRole.guest);
      expect(container.read(adFlagsProvider), _allOn);
    });

    test('일반 SNS 사용자: 광고 그대로', () async {
      store.saved = session();
      final container = await restored();
      expect(container.read(accountRoleProvider), AccountRole.user);
      expect(container.read(adFlagsProvider), _allOn);
    });

    test('세션 복원 중에는 광고 OFF (면제 계정에 광고 깜빡임 방지)', () {
      final container = createContainer();
      expect(container.read(authSessionProvider).isLoading, isTrue);
      expect(container.read(adFlagsProvider).anyEnabled, isFalse);
    });

    for (final (label, owner) in [
      ('is_staff', user(isStaff: true)),
      ('is_superuser', user(isSuperuser: true)),
    ]) {
      test('$label 사용자: 광고 전부 OFF, 광고 SDK 미호출', () async {
        store.saved = session(owner: owner);
        final container = await restored();

        expect(container.read(isAdFreeProvider), isTrue);
        final service = container.read(adServiceProvider);
        expect(service.flags.anyEnabled, isFalse);
        expect(await service.loadNativeAd(), isNull);
        expect(await service.showInterstitial(), isFalse);
        expect(await service.runRewardGate(), isTrue);
      });
    }
  });

  group('로그인', () {
    test('SNS 자격 증명을 서버로 보내고 세션 저장', () async {
      api.signInResult = session(owner: user(isSuperuser: true));
      final container = await restored();

      await container
          .read(authSessionProvider.notifier)
          .signIn(SnsProvider.google);

      expect(api.lastCredential, isA<GoogleCredential>());
      expect(store.saved, api.signInResult);
      expect(container.read(adFlagsProvider).anyEnabled, isFalse);
    });

    test('SNS 취소 시 예외 전달, 상태 변화 없음', () async {
      sns.error = const AuthException(AuthFailure.cancelled);
      final container = await restored();

      await expectLater(
        container.read(authSessionProvider.notifier).signIn(SnsProvider.kakao),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.cancelled,
          ),
        ),
      );
      expect(container.read(authSessionProvider).value, isNull);
      expect(store.saved, isNull);
    });
  });

  group('서버 재검증 (관리자 콘솔의 역할 변경 반영)', () {
    test('스태프 권한이 부여되면 광고 OFF로 전환', () async {
      store.saved = session();
      final container = await restored();
      expect(container.read(isAdFreeProvider), isFalse);

      api.meResponse.complete(user(isStaff: true));
      await pumpEventQueue();

      expect(container.read(accountRoleProvider), AccountRole.staff);
      expect(store.saved!.user.isStaff, isTrue);
      expect(container.read(adFlagsProvider).anyEnabled, isFalse);
    });

    test('스태프 권한이 회수되면 광고 다시 적용', () async {
      store.saved = session(owner: user(isStaff: true));
      final container = await restored();

      api.meResponse.complete(user());
      await pumpEventQueue();

      expect(container.read(adFlagsProvider), _allOn);
    });

    test('access 만료 → refresh 후 재시도, 새 토큰 저장', () async {
      store.saved = session(access: 'old');
      api.expiredAccessTokens.add('old');
      api.refreshResult = session(access: 'new', refresh: 'r2');
      api.meResponse.complete(user(isSuperuser: true));

      final container = await restored();
      await pumpEventQueue();

      expect(api.refreshCalls, 1);
      expect(store.saved!.accessToken, 'new');
      expect(store.saved!.refreshToken, 'r2');
      expect(container.read(accountRoleProvider), AccountRole.superuser);
    });

    test('refresh도 거부되면 로그아웃 처리 → 광고 다시 적용', () async {
      store.saved = session(access: 'old', owner: user(isStaff: true));
      api.expiredAccessTokens.add('old');
      api.refreshFailure = AuthFailure.unauthorized;

      final container = await restored();
      await pumpEventQueue();

      expect(container.read(authSessionProvider).value, isNull);
      expect(store.saved, isNull);
      expect(container.read(adFlagsProvider), _allOn);
    });

    test('네트워크 오류면 캐시된 역할 유지 (오프라인)', () async {
      store.saved = session(owner: user(isStaff: true));
      final container = await restored();

      api.meResponse.completeError(const AuthException(AuthFailure.network));
      await pumpEventQueue();

      expect(container.read(isAdFreeProvider), isTrue);
      expect(store.saved, isNotNull);
    });
  });

  group('로그아웃/탈퇴', () {
    test('로그아웃: 서버 실패해도 로컬 삭제 + SNS 로그아웃', () async {
      store.saved = session(refresh: 'rx');
      final container = await restored();

      await container.read(authSessionProvider.notifier).signOut();

      expect(api.loggedOut, ['rx']);
      expect(store.saved, isNull);
      expect(sns.signedOut, [SnsProvider.kakao]);
    });

    test('탈퇴 성공 시 세션 삭제', () async {
      store.saved = session(access: 'ax');
      final container = await restored();

      await container.read(authSessionProvider.notifier).deleteAccount();

      expect(api.deletedWith, ['ax']);
      expect(store.saved, isNull);
    });

    test('탈퇴: access 만료면 refresh 후 재시도', () async {
      store.saved = session(access: 'old');
      api.expiredAccessTokens.add('old');
      api.refreshResult = session(access: 'new', refresh: 'r2');
      final container = await restored();

      await container.read(authSessionProvider.notifier).deleteAccount();

      expect(api.deletedWith, ['new']);
      expect(store.saved, isNull);
    });

    test('탈퇴 실패 시 세션 유지 (탈퇴된 것처럼 보이면 안 됨)', () async {
      store.saved = session();
      api.deleteFailure = AuthFailure.network;
      final container = await restored();

      await expectLater(
        container.read(authSessionProvider.notifier).deleteAccount(),
        throwsA(isA<AuthException>()),
      );
      expect(store.saved, isNotNull);
      expect(container.read(authSessionProvider).value, isNotNull);
    });
  });
}
