import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';

import 'app.dart';
import 'core/env.dart';
import 'models/ad_flags.dart';
import 'providers/ad_providers.dart';
import 'services/remote_config_service.dart';

/// 초기화 순서: 바인딩 → 세로 고정 → Kakao SDK → Firebase → Remote Config → ProviderScope.
/// 광고 SDK는 첫 광고 요청 직전에 AdService가 지연 초기화한다 (동의/ATT 포함).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  if (Env.kakaoNativeAppKey.isNotEmpty) {
    await KakaoSdk.init(nativeAppKey: Env.kakaoNativeAppKey);
  }

  final adFlags = await _loadAdFlags();

  runApp(
    ProviderScope(
      overrides: [remoteAdFlagsProvider.overrideWithValue(adFlags)],
      child: const LikeZzixApp(),
    ),
  );
}

/// Firebase/Remote Config가 실패해도 앱은 기본값(광고 OFF)으로 실행된다.
Future<AdFlags> _loadAdFlags() async {
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
