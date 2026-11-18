import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_unit_ids.dart';
import '../models/ad_flags.dart';
import 'ad_consent_service.dart';

/// 광고 SDK 초기화(동의 포함). 광고 요청이 가능하면 true.
typedef AdsInitializer = Future<bool> Function();

/// 광고 단위 ID 조회 함수 (테스트에서 교체 가능).
typedef AdUnitIdResolver = String? Function(AdFormat format);

/// 모든 광고 호출의 단일 진입점.
///
/// 모든 public 메서드는 첫 줄에서 Remote Config 플래그를 확인하고,
/// false면 SDK를 건드리지 않고 즉시 반환한다.
/// SDK 초기화(UMP → ATT → MobileAds)는 첫 광고 요청 직전에 한 번만 수행한다.
class AdService {
  AdService({
    required this.flags,
    AdsInitializer? initializer,
    AdUnitIdResolver? adUnitIdResolver,
  }) : _initializer = initializer ?? _defaultInitializer,
       _adUnitId = adUnitIdResolver ?? AdUnitIds.of;

  final AdFlags flags;
  final AdsInitializer _initializer;
  final AdUnitIdResolver _adUnitId;

  Future<bool>? _initFuture;
  InterstitialAd? _interstitial;
  bool _interstitialLoading = false;
  bool _disposed = false;

  static Future<bool> _defaultInitializer() async {
    final canRequestAds = await AdConsentService().gatherConsent();
    if (!canRequestAds) return false;
    await MobileAds.instance.initialize();
    return true;
  }

  /// 광고 SDK를 준비. 플래그가 모두 꺼져 있으면 동의 팝업도 띄우지 않음.
  Future<bool> ensureInitialized() {
    if (!flags.anyEnabled || _disposed) return Future.value(false);
    return _initFuture ??= _initializer().catchError((Object error) {
      debugPrint('[Ads] 초기화 실패: $error');
      _initFuture = null;
      return false;
    });
  }

  // ---------------------------------------------------------------------------
  // Native (프리셋 그리드 5번째 칸)
  // ---------------------------------------------------------------------------

  /// 네이티브 광고를 로드해 반환. 비활성/실패 시 null → 호출부는 기본 프리셋 UI 사용.
  /// 반환된 광고의 dispose 책임은 호출부(위젯)에 있음.
  Future<NativeAd?> loadNativeAd({
    TemplateType templateType = TemplateType.small,
  }) async {
    if (!flags.showNativeAd) return null;
    final unitId = _adUnitId(AdFormat.native);
    if (unitId == null || !await ensureInitialized()) return null;

    final completer = Completer<NativeAd?>();
    final ad = NativeAd(
      adUnitId: unitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(templateType: templateType),
      listener: NativeAdListener(
        onAdLoaded: (ad) => completer.complete(ad as NativeAd),
        onAdFailedToLoad: (ad, error) {
          debugPrint('[Ads] native 로드 실패: ${error.message}');
          ad.dispose();
          completer.complete(null);
        },
      ),
    );
    await ad.load();
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Interstitial (저장 N회마다)
  // ---------------------------------------------------------------------------

  /// 다음 노출을 위해 전면 광고를 미리 로드.
  Future<void> preloadInterstitial() async {
    if (!flags.showInterstitialAd) return;
    if (_interstitial != null || _interstitialLoading) return;
    final unitId = _adUnitId(AdFormat.interstitial);
    if (unitId == null || !await ensureInitialized()) return;

    _interstitialLoading = true;
    await InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialLoading = false;
          if (_disposed) {
            ad.dispose();
            return;
          }
          _interstitial = ad;
        },
        onAdFailedToLoad: (error) {
          _interstitialLoading = false;
          debugPrint('[Ads] interstitial 로드 실패: ${error.message}');
        },
      ),
    );
  }

  /// 전면 광고를 표시하고 닫힐 때까지 기다림. 실제로 표시됐으면 true.
  Future<bool> showInterstitial() async {
    if (!flags.showInterstitialAd) return false;
    final ad = _interstitial;
    if (ad == null) {
      unawaited(preloadInterstitial());
      return false;
    }
    _interstitial = null;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        completer.complete(true);
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[Ads] interstitial 표시 실패: ${error.message}');
        ad.dispose();
        completer.complete(false);
        unawaited(preloadInterstitial());
      },
    );
    await ad.show();
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Rewarded (커스텀 실루엣 생성 게이트)
  // ---------------------------------------------------------------------------

  /// 보상형 광고 게이트. true면 호출부에서 보호된 기능을 실행.
  ///
  /// - 플래그 OFF: 즉시 true
  /// - 광고 시청 완료(onUserEarnedReward): true
  /// - 시청 중 닫음: false
  /// - 광고 준비 실패(SDK/동의/로드/표시 실패): 사용자 불이익 방지를 위해 true
  Future<bool> runRewardGate() async {
    if (!flags.showRewardedAd) return true;
    final unitId = _adUnitId(AdFormat.rewarded);
    if (unitId == null || !await ensureInitialized()) return true;

    final ad = await _loadRewarded(unitId);
    if (ad == null) return true;

    var earned = false;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[Ads] rewarded 표시 실패: ${error.message}');
        ad.dispose();
        completer.complete(true);
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => earned = true);
    return completer.future;
  }

  Future<RewardedAd?> _loadRewarded(String unitId) {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: completer.complete,
        onAdFailedToLoad: (error) {
          debugPrint('[Ads] rewarded 로드 실패: ${error.message}');
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  void dispose() {
    _disposed = true;
    _interstitial?.dispose();
    _interstitial = null;
  }
}
