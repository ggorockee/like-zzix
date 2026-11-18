/// Firebase Remote Config 파라미터 키와 기본값.
///
/// PRD 규칙: 런칭 초기에는 모든 광고 플래그 기본값이 `false`.
abstract final class RemoteConfigKeys {
  static const showNativeAd = 'show_native_ad';
  static const showInterstitialAd = 'show_interstitial_ad';
  static const showRewardedAd = 'show_rewarded_ad';
  static const interstitialAdInterval = 'interstitial_ad_interval';

  static const defaultInterstitialAdInterval = 3;

  static const Map<String, Object> defaults = {
    showNativeAd: false,
    showInterstitialAd: false,
    showRewardedAd: false,
    interstitialAdInterval: defaultInterstitialAdInterval,
  };
}
