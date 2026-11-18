import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/core/remote_config_keys.dart';
import 'package:likezzix/models/ad_flags.dart';

void main() {
  group('AdFlags', () {
    test('PRD 기본값: 모든 광고 OFF, 전면 광고 간격 3', () {
      expect(AdFlags.defaults.showNativeAd, isFalse);
      expect(AdFlags.defaults.showInterstitialAd, isFalse);
      expect(AdFlags.defaults.showRewardedAd, isFalse);
      expect(AdFlags.defaults.interstitialAdInterval, 3);
      expect(AdFlags.defaults.anyEnabled, isFalse);
    });

    test('Remote Config 기본값: PRD 광고 4개 키 + 업데이트 안내 없음', () {
      expect(RemoteConfigKeys.defaults, containsPair('show_native_ad', false));
      expect(
        RemoteConfigKeys.defaults,
        containsPair('show_interstitial_ad', false),
      );
      expect(
        RemoteConfigKeys.defaults,
        containsPair('show_rewarded_ad', false),
      );
      expect(
        RemoteConfigKeys.defaults,
        containsPair('interstitial_ad_interval', 3),
      );
      // 버전 기본값 0.0.0 → 어떤 버전도 업데이트 팝업이 뜨지 않음
      for (final key in [
        'android_min_version',
        'ios_min_version',
        'android_latest_version',
        'ios_latest_version',
      ]) {
        expect(RemoteConfigKeys.defaults, containsPair(key, '0.0.0'));
      }
    });

    test('전면 광고 간격이 1 미만이면 기본값으로 보정', () {
      for (final invalid in [0, -5]) {
        final flags = AdFlags(
          showNativeAd: false,
          showInterstitialAd: true,
          showRewardedAd: false,
          interstitialAdInterval: invalid,
        );
        expect(flags.interstitialAdInterval, 3);
      }
    });

    test('하나라도 켜지면 anyEnabled', () {
      const flags = AdFlags(
        showNativeAd: false,
        showInterstitialAd: false,
        showRewardedAd: true,
        interstitialAdInterval: 5,
      );
      expect(flags.anyEnabled, isTrue);
      expect(flags.interstitialAdInterval, 5);
    });
  });
}
