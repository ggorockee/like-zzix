import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../core/remote_config_keys.dart';
import '../models/ad_flags.dart';

/// Firebase Remote Config 래퍼.
///
/// 초기화 실패(오프라인, 타임아웃 등)는 앱 실행을 막지 않고 기본값으로 진행.
class RemoteConfigService {
  RemoteConfigService(this._remoteConfig);

  final FirebaseRemoteConfig _remoteConfig;

  Future<void> initialize() async {
    try {
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: kReleaseMode
              ? const Duration(hours: 1)
              : Duration.zero,
        ),
      );
      await _remoteConfig.setDefaults(RemoteConfigKeys.defaults);
      await _remoteConfig.fetchAndActivate();
    } on Exception catch (error, stackTrace) {
      debugPrint('[RemoteConfig] 기본값으로 진행: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
    }
  }

  AdFlags get adFlags => AdFlags(
    showNativeAd: _remoteConfig.getBool(RemoteConfigKeys.showNativeAd),
    showInterstitialAd: _remoteConfig.getBool(
      RemoteConfigKeys.showInterstitialAd,
    ),
    showRewardedAd: _remoteConfig.getBool(RemoteConfigKeys.showRewardedAd),
    interstitialAdInterval: _remoteConfig.getInt(
      RemoteConfigKeys.interstitialAdInterval,
    ),
  );
}
