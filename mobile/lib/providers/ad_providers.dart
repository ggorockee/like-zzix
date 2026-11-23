import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ad_flags.dart';
import '../services/ad_service.dart';
import '../services/save_ad_controller.dart';
import '../services/app_initializer.dart';
import '../services/telemetry_service.dart';
import 'api_providers.dart';

/// 앱 초기화(Firebase → Crashlytics → Remote Config). 스플래시 화면이 이 작업을 기다린다.
final appInitProvider = FutureProvider<AppBootstrap>((ref) => initializeApp());

/// Remote Config에서 읽은 광고 플래그 (원본 값).
/// 초기화가 끝나기 전·실패 시에는 PRD 기본값(모두 OFF).
final remoteAdFlagsProvider = Provider<AdFlags>(
  (ref) => ref.watch(appInitProvider).value?.adFlags ?? AdFlags.defaults,
);

/// 실제로 적용되는 광고 플래그.
/// 계정별 광고 면제(M7)가 들어오면 이 Provider에서 함께 판단한다.
final adFlagsProvider = Provider<AdFlags>(
  (ref) => ref.watch(remoteAdFlagsProvider),
);

/// 플래그가 바뀌면 이전 AdService는 dispose되어 미리 로드된 광고도 폐기된다.
final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService(
    flags: ref.watch(adFlagsProvider),
    onLoadFailed: () =>
        ref.read(telemetryProvider)?.record(AppEvent.adLoadFailed),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// 저장 N회마다 전면 광고. 촬영을 방해하지 않도록 잠금 중에는 미뤘다가 잠금을 풀 때 보여 준다.
final saveAdProvider = Provider<SaveAdController>(
  (ref) => SaveAdController(
    ads: ref.watch(adServiceProvider),
    onShown: () =>
        ref.read(telemetryProvider)?.record(AppEvent.adInterstitialShown),
  ),
);
