import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/ad_flags.dart';
import '../models/app_version.dart';
import 'remote_config_service.dart';

/// 앱 시작 시 한 번 읽어 두는 원격 설정.
@immutable
class AppBootstrap {
  const AppBootstrap({
    required this.adFlags,
    required this.updatePolicy,
    required this.currentVersion,
  });

  static const fallback = AppBootstrap(
    adFlags: AdFlags.defaults,
    updatePolicy: UpdatePolicy.none,
    currentVersion: AppVersion.zero,
  );

  final AdFlags adFlags;
  final UpdatePolicy updatePolicy;
  final AppVersion currentVersion;
}

/// 앱 시작 시 초기화: Firebase → Crashlytics → Remote Config(광고 플래그·업데이트 정책).
/// 실패해도 앱은 기본값(광고 OFF, 업데이트 안내 없음)으로 실행된다.
/// 광고 SDK는 첫 광고 요청 직전에 AdService가 지연 초기화한다 (동의/ATT 포함).
Future<AppBootstrap> initializeApp() async {
  final info = await PackageInfo.fromPlatform();
  final currentVersion = AppVersion.parse(info.version);
  try {
    // 네이티브 설정 파일(google-services.json / GoogleService-Info.plist)을 사용.
    await Firebase.initializeApp();
  } on Exception catch (error) {
    debugPrint('[Firebase] 초기화 실패, 기본값으로 진행: $error');
    return AppBootstrap(
      adFlags: AdFlags.defaults,
      updatePolicy: UpdatePolicy.none,
      currentVersion: currentVersion,
    );
  }

  await _setUpCrashlytics();

  final remoteConfig = RemoteConfigService(FirebaseRemoteConfig.instance);
  await remoteConfig.initialize();
  final bootstrap = AppBootstrap(
    adFlags: remoteConfig.adFlags,
    updatePolicy: remoteConfig.updatePolicy(
      isIOS: Platform.isIOS,
      packageName: info.packageName,
    ),
    currentVersion: currentVersion,
  );
  debugPrint(
    '[RemoteConfig] ${bootstrap.adFlags}, 버전 $currentVersion '
    '(최소 ${bootstrap.updatePolicy.minVersion}, 최신 ${bootstrap.updatePolicy.latestVersion})',
  );
  return bootstrap;
}

/// 릴리스 빌드에서만 크래시 수집. Flutter 프레임워크 오류와 비동기 오류 모두 기록.
Future<void> _setUpCrashlytics() async {
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(kReleaseMode);
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    crashlytics.recordError(error, stack, fatal: true);
    return true;
  };
}
