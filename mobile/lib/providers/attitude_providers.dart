import 'dart:async';

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../models/angle_spec.dart';
import '../models/angle_state.dart';
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

/// 선택한 프리셋의 권장 각도 대비 상태. 프리셋이 없으면 수평(0°)만 기준.
final angleGuideProvider =
    NotifierProvider.autoDispose<AngleGuideNotifier, AngleGuide?>(
      AngleGuideNotifier.new,
    );

class AngleGuideNotifier extends Notifier<AngleGuide?> {
  @override
  AngleGuide? build() {
    final spec = ref.watch(selectedPresetProvider)?.angle ?? AngleSpec.level;
    final front = ref.watch(activeLensProvider) == CameraLensDirection.front;
    final machine = AngleStateMachine(spec);
    ref.listen(attitudeProvider, (_, next) {
      final attitude = next.value;
      if (attitude == null) return;
      state = machine.add(front ? attitude.forFrontCamera : attitude);
    }, fireImmediately: true);
    return null;
  }
}
