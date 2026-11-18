import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ad_flags.dart';
import '../services/ad_service.dart';
import 'auth_providers.dart';

/// 앱 시작 시 Remote Config에서 읽은 광고 플래그 (원본 값).
/// `main.dart`에서 실제 값으로 override하며, override가 없으면 PRD 기본값(모두 OFF).
final remoteAdFlagsProvider = Provider<AdFlags>((ref) => AdFlags.defaults);

/// 실제로 적용되는 광고 플래그.
/// - 로그인 세션 복원 중: 모두 OFF (면제 계정에 광고가 잠깐 뜨는 것 방지)
/// - 광고 면제 계정(is_staff / is_superuser): Remote Config 값과 관계없이 모두 OFF
final adFlagsProvider = Provider<AdFlags>((ref) {
  if (ref.watch(authSessionProvider).isLoading) return AdFlags.disabled;
  if (ref.watch(isAdFreeProvider)) return AdFlags.disabled;
  return ref.watch(remoteAdFlagsProvider);
});

/// 역할이 바뀌면 플래그가 바뀌고, 이전 AdService는 dispose되어
/// 미리 로드된 광고도 함께 폐기된다.
final adServiceProvider = Provider<AdService>((ref) {
  final service = AdService(flags: ref.watch(adFlagsProvider));
  ref.onDispose(service.dispose);
  return service;
});
