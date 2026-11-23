import 'dart:async';

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/attitude.dart';
import 'camera_providers.dart';
import 'preset_providers.dart';

/// 실시간 휴대폰 자세 (가속도계 + 자이로, 약 50Hz).
final attitudeProvider = StreamProvider.autoDispose<Attitude>((ref) {
  final filter = AttitudeFilter();
  final controller = StreamController<Attitude>();
  final gyro = gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval)
      .listen(
        (e) => filter.addGyroscope(e.x, e.y, e.z, e.timestamp),
        // 자이로가 없는 기기: 가속도계만으로 계속
        onError: (Object e) => debugPrint('[Attitude] 자이로 사용 불가: $e'),
        cancelOnError: true,
      );
  final accel =
      accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (e) =>
            controller.add(filter.addAccelerometer(e.x, e.y, e.z, e.timestamp)),
        onError: controller.addError,
      );
  ref.onDispose(() {
    unawaited(gyro.cancel());
    unawaited(accel.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
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
    final front = ref.watch(activeLensProvider) == CameraLensDirection.front;
    final matcher = AngleMatcher();
    ref.listen(attitudeProvider, (_, next) {
      final attitude = next.value;
      if (attitude == null) return;
      final wasMatched = state?.matched ?? false;
      final guide = matcher.evaluate(
        front ? attitude.forFrontCamera : attitude,
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
