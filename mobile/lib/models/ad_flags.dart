import 'package:flutter/foundation.dart';

import '../core/remote_config_keys.dart';

/// Remote Config에서 읽은 광고 노출 플래그 (앱 실행 단위로 고정).
@immutable
class AdFlags {
  const AdFlags({
    required this.showNativeAd,
    required this.showInterstitialAd,
    required this.showRewardedAd,
    required int interstitialAdInterval,
  }) : interstitialAdInterval = interstitialAdInterval < 1
           ? RemoteConfigKeys.defaultInterstitialAdInterval
           : interstitialAdInterval;

  /// Remote Config 조회 실패 시에도 사용하는 PRD 기본값 (광고 모두 OFF).
  static const defaults = AdFlags(
    showNativeAd: false,
    showInterstitialAd: false,
    showRewardedAd: false,
    interstitialAdInterval: RemoteConfigKeys.defaultInterstitialAdInterval,
  );

  /// 모든 광고 OFF (광고 면제 계정용). 간격 값은 사용되지 않음.
  static const disabled = defaults;

  final bool showNativeAd;
  final bool showInterstitialAd;
  final bool showRewardedAd;

  /// 전면 광고를 노출할 저장 횟수 간격. 1 미만 값은 기본값(3)으로 보정.
  final int interstitialAdInterval;

  bool get anyEnabled => showNativeAd || showInterstitialAd || showRewardedAd;

  @override
  bool operator ==(Object other) =>
      other is AdFlags &&
      other.showNativeAd == showNativeAd &&
      other.showInterstitialAd == showInterstitialAd &&
      other.showRewardedAd == showRewardedAd &&
      other.interstitialAdInterval == interstitialAdInterval;

  @override
  int get hashCode => Object.hash(
    showNativeAd,
    showInterstitialAd,
    showRewardedAd,
    interstitialAdInterval,
  );

  @override
  String toString() =>
      'AdFlags(native: $showNativeAd, interstitial: $showInterstitialAd, '
      'rewarded: $showRewardedAd, interval: $interstitialAdInterval)';
}
