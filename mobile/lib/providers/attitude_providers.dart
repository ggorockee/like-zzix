import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/attitude.dart';
import 'preset_providers.dart';

/// 실시간 휴대폰 자세 (가속도계 + 저역 통과 필터, UI 주기).
final attitudeProvider = StreamProvider.autoDispose<Attitude>((ref) {
  final filter = GravityFilter();
  return accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
      .map((e) => filter.add(e.x, e.y, e.z));
});

/// 선택한 프리셋의 목표 각도 대비 안내. 프리셋이 없으면 수평(0°)만 기준.
/// 일치 상태로 들어가는 순간 1회 햅틱.
final angleGuideProvider =
    NotifierProvider.autoDispose<AngleGuideNotifier, AngleGuide?>(
      AngleGuideNotifier.new,
    );

class AngleGuideNotifier extends Notifier<AngleGuide?> {
  @override
  AngleGuide? build() {
    final preset = ref.watch(selectedPresetProvider);
    final matcher = AngleMatcher();
    ref.listen(attitudeProvider, (_, next) {
      final attitude = next.value;
      if (attitude == null) return;
      final wasMatched = state?.matched ?? false;
      final guide = matcher.evaluate(
        attitude,
        targetPitchDeg: preset?.pitchDeg ?? 0,
        targetRollDeg: preset?.rollDeg ?? 0,
      );
      if (guide.matched && !wasMatched && preset != null) {
        HapticFeedback.mediumImpact();
      }
      state = guide;
    }, fireImmediately: true);
    return null;
  }
}
