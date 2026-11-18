import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/ad_flags.dart';
import 'package:likezzix/services/ad_service.dart';

void main() {
  group('AdService 플래그 선검사 (플래그 OFF면 SDK를 건드리지 않음)', () {
    late int initCalls;
    late AdService service;

    setUp(() {
      initCalls = 0;
      service = AdService(
        flags: AdFlags.defaults,
        initializer: () async {
          initCalls++;
          return true;
        },
      );
    });

    test('ensureInitialized: 초기화/동의 흐름을 실행하지 않음', () async {
      expect(await service.ensureInitialized(), isFalse);
      expect(initCalls, 0);
    });

    test('loadNativeAd: null → 기본 프리셋 UI로 대체', () async {
      expect(await service.loadNativeAd(), isNull);
      expect(initCalls, 0);
    });

    test('showInterstitial: 표시하지 않음', () async {
      await service.preloadInterstitial();
      expect(await service.showInterstitial(), isFalse);
      expect(initCalls, 0);
    });

    test('runRewardGate: 광고 없이 즉시 허용', () async {
      expect(await service.runRewardGate(), isTrue);
      expect(initCalls, 0);
    });
  });

  group('AdService 플래그 ON', () {
    const rewardedOnly = AdFlags(
      showNativeAd: false,
      showInterstitialAd: false,
      showRewardedAd: true,
      interstitialAdInterval: 3,
    );

    test('초기화는 한 번만 수행', () async {
      var initCalls = 0;
      final service = AdService(
        flags: rewardedOnly,
        initializer: () async {
          initCalls++;
          return true;
        },
      );
      await Future.wait([
        service.ensureInitialized(),
        service.ensureInitialized(),
      ]);
      expect(initCalls, 1);
    });

    test('동의 거부 등으로 광고 요청 불가 시 보상 게이트는 허용', () async {
      final service = AdService(
        flags: rewardedOnly,
        initializer: () async => false,
      );
      expect(await service.runRewardGate(), isTrue);
    });

    test('광고 단위 ID가 없으면 보상 게이트는 허용', () async {
      var initCalls = 0;
      final service = AdService(
        flags: rewardedOnly,
        initializer: () async {
          initCalls++;
          return true;
        },
        adUnitIdResolver: (_) => null,
      );
      expect(await service.runRewardGate(), isTrue);
      expect(initCalls, 0);
    });

    test('초기화 예외 시 false를 반환하고 다음 호출에서 재시도', () async {
      var initCalls = 0;
      final service = AdService(
        flags: rewardedOnly,
        initializer: () async {
          initCalls++;
          if (initCalls == 1) throw Exception('network');
          return true;
        },
      );
      expect(await service.ensureInitialized(), isFalse);
      expect(await service.ensureInitialized(), isTrue);
      expect(initCalls, 2);
    });
  });
}
