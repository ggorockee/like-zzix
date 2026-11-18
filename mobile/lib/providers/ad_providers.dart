import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ad_flags.dart';
import '../services/ad_service.dart';
import '../services/app_initializer.dart';

/// 앱 초기화(Firebase → Remote Config). 스플래시 화면이 이 작업을 기다린다.
final appInitProvider = FutureProvider<AdFlags>((ref) => initializeApp());

/// Remote Config에서 읽은 광고 플래그 (원본 값).
/// 초기화가 끝나기 전·실패 시에는 PRD 기본값(모두 OFF).
final remoteAdFlagsProvider = Provider<AdFlags>(
  (ref) => ref.watch(appInitProvider).value ?? AdFlags.defaults,
);

/// 실제로 적용되는 광고 플래그.
/// 계정별 광고 면제(M7)가 들어오면 이 Provider에서 함께 판단한다.
final adFlagsProvider = Provider<AdFlags>(
  (ref) => ref.watch(remoteAdFlagsProvider),
);

/// 플래그가 바뀌면 이전 AdService는 dispose되어 미리 로드된 광고도 폐기된다.
final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService(flags: ref.watch(adFlagsProvider));
  ref.onDispose(service.dispose);
  return service;
});
