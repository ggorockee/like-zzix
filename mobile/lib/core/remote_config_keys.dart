/// Firebase Remote Config 파라미터 키와 기본값.
///
/// 템플릿(실제 콘솔 값)은 `firebase/remoteconfig.template.json`에서 버전 관리한다.
/// PRD 규칙: 런칭 초기에는 모든 광고 플래그 기본값이 `false`.
abstract final class RemoteConfigKeys {
  static const showNativeAd = 'show_native_ad';
  static const showInterstitialAd = 'show_interstitial_ad';
  static const showRewardedAd = 'show_rewarded_ad';
  static const interstitialAdInterval = 'interstitial_ad_interval';

  /// 이 버전보다 낮으면 강제 업데이트 (닫을 수 없는 팝업)
  static const androidMinVersion = 'android_min_version';
  static const iosMinVersion = 'ios_min_version';

  /// 이 버전보다 낮으면 선택 업데이트 (버전당 1회, "나중에" 가능)
  static const androidLatestVersion = 'android_latest_version';
  static const iosLatestVersion = 'ios_latest_version';

  /// 스토어 링크. Android는 비어 있으면 패키지 이름으로 Play 스토어 링크를 만든다.
  /// iOS는 App Store 등록 후 `https://apps.apple.com/app/id<번호>`를 넣는다.
  static const androidStoreUrl = 'android_store_url';
  static const iosStoreUrl = 'ios_store_url';

  /// 업데이트 팝업 본문 (비우면 기본 문구)
  static const updateMessage = 'update_message';

  static const defaultInterstitialAdInterval = 3;

  static const Map<String, Object> defaults = {
    showNativeAd: false,
    showInterstitialAd: false,
    showRewardedAd: false,
    interstitialAdInterval: defaultInterstitialAdInterval,
    androidMinVersion: '0.0.0',
    iosMinVersion: '0.0.0',
    androidLatestVersion: '0.0.0',
    iosLatestVersion: '0.0.0',
    androidStoreUrl: '',
    iosStoreUrl: '',
    updateMessage: '',
  };
}
