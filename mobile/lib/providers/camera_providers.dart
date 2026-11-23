import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/capture_service.dart';
import '../services/volume_button_service.dart';

/// 기기의 카메라 목록 (시뮬레이터 등에서는 빈 목록).
final availableCamerasProvider = FutureProvider<List<CameraDescription>>(
  (ref) => availableCameras(),
);

/// 지금 쓰는 렌즈 (전면이면 각도 안내가 뒤집힌다). 카메라 화면이 갱신한다.
final activeLensProvider =
    NotifierProvider<ActiveLensNotifier, CameraLensDirection>(
      ActiveLensNotifier.new,
    );

class ActiveLensNotifier extends Notifier<CameraLensDirection> {
  @override
  CameraLensDirection build() => CameraLensDirection.back;

  void set(CameraLensDirection lens) => state = lens;
}

final captureServiceProvider = Provider<CaptureService>(
  (ref) => CaptureService(),
);

final volumeButtonProvider = Provider<VolumeButtonService>(
  (ref) => VolumeButtonService(),
);

/// 스토어 스크린샷 전용: null이 아니면 카메라 프리뷰 자리에 이 위젯을 그린다.
/// 시뮬레이터에는 카메라가 없어서 `integration_test/store_screenshots_test.dart`에서만 override한다.
final cameraBackdropProvider = Provider<Widget?>((ref) => null);
