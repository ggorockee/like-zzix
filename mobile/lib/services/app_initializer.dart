import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

import '../models/ad_flags.dart';
import 'remote_config_service.dart';

/// 앱 시작 시 초기화: Firebase → Remote Config → 광고 플래그.
/// 실패해도 앱은 기본값(광고 OFF)으로 실행된다.
/// 광고 SDK는 첫 광고 요청 직전에 AdService가 지연 초기화한다 (동의/ATT 포함).
Future<AdFlags> initializeApp() async {
  try {
    // 네이티브 설정 파일(google-services.json / GoogleService-Info.plist)을 사용.
    await Firebase.initializeApp();
  } on Exception catch (error) {
    debugPrint('[Firebase] 초기화 실패, 기본값으로 진행: $error');
    return AdFlags.defaults;
  }

  final remoteConfig = RemoteConfigService(FirebaseRemoteConfig.instance);
  await remoteConfig.initialize();
  final flags = remoteConfig.adFlags;
  debugPrint('[RemoteConfig] $flags');
  return flags;
}
