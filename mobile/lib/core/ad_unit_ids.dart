import 'package:flutter/foundation.dart';

enum AdFormat { native, interstitial, rewarded }

/// 광고 단위 ID.
///
/// - 디버그/프로필 빌드: 항상 Google 공식 테스트 광고 단위 ID 사용.
/// - 릴리스 빌드: `--dart-define-from-file=env/prod.json` 값 사용.
///   값이 비어 있으면 `null`을 반환하고 해당 광고는 로드하지 않음.
abstract final class AdUnitIds {
  static const _androidTest = {
    AdFormat.native: 'ca-app-pub-3940256099942544/2247696110',
    AdFormat.interstitial: 'ca-app-pub-3940256099942544/1033173712',
    AdFormat.rewarded: 'ca-app-pub-3940256099942544/5224354917',
  };

  static const _iosTest = {
    AdFormat.native: 'ca-app-pub-3940256099942544/3986624511',
    AdFormat.interstitial: 'ca-app-pub-3940256099942544/4411468910',
    AdFormat.rewarded: 'ca-app-pub-3940256099942544/1712485313',
  };

  static const _androidProd = {
    AdFormat.native: String.fromEnvironment('ADMOB_ANDROID_NATIVE'),
    AdFormat.interstitial: String.fromEnvironment('ADMOB_ANDROID_INTERSTITIAL'),
    AdFormat.rewarded: String.fromEnvironment('ADMOB_ANDROID_REWARDED'),
  };

  static const _iosProd = {
    AdFormat.native: String.fromEnvironment('ADMOB_IOS_NATIVE'),
    AdFormat.interstitial: String.fromEnvironment('ADMOB_IOS_INTERSTITIAL'),
    AdFormat.rewarded: String.fromEnvironment('ADMOB_IOS_REWARDED'),
  };

  static String? of(
    AdFormat format, {
    TargetPlatform? platform,
    bool useTestIds = !kReleaseMode,
  }) {
    final target = platform ?? defaultTargetPlatform;
    final Map<AdFormat, String> table = switch (target) {
      TargetPlatform.android => useTestIds ? _androidTest : _androidProd,
      TargetPlatform.iOS => useTestIds ? _iosTest : _iosProd,
      _ => const {},
    };
    final id = table[format];
    return (id == null || id.isEmpty) ? null : id;
  }
}
