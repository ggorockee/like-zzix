import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_service.dart';

/// 사진 저장 횟수를 세어 [AdFlags.interstitialAdInterval]회마다 전면 광고를 보여 준다.
/// 횟수는 앱을 다시 켜도 이어진다.
class SaveAdController {
  SaveAdController({
    required this.ads,
    this.onShown,
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  static const _countKey = 'ad_save_count';

  final AdService ads;
  final VoidCallback? onShown;
  final Future<SharedPreferences> Function() _prefs;

  /// 저장 성공 시 호출. [locked]면 횟수만 세고 광고는 미룬다.
  Future<void> onSaved({required bool locked}) async {
    if (!ads.flags.showInterstitialAd) return;
    final store = await _prefs();
    final count = (store.getInt(_countKey) ?? 0) + 1;
    await store.setInt(_countKey, count);
    // 다음 노출을 위해 미리 받아 둔다 (첫 저장 뒤에 동의·추적 안내가 나온다)
    unawaited(ads.preloadInterstitial());
    if (!locked) await showIfDue();
  }

  /// 횟수가 찼으면 광고를 보여 준다. 준비되지 않았으면 다음 기회로 미룬다.
  Future<void> showIfDue() async {
    if (!ads.flags.showInterstitialAd) return;
    final store = await _prefs();
    final count = store.getInt(_countKey) ?? 0;
    if (count < ads.flags.interstitialAdInterval) return;
    if (await ads.showInterstitial()) {
      await store.setInt(_countKey, 0);
      onShown?.call();
    }
  }
}
