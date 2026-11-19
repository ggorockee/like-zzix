import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/capture_service.dart';

/// 기기의 카메라 목록 (시뮬레이터 등에서는 빈 목록).
final availableCamerasProvider = FutureProvider<List<CameraDescription>>(
  (ref) => availableCameras(),
);

final captureServiceProvider = Provider<CaptureService>(
  (ref) => CaptureService(),
);

/// 스토어 스크린샷 전용: null이 아니면 카메라 프리뷰 자리에 이 위젯을 그린다.
/// 시뮬레이터에는 카메라가 없어서 `integration_test/store_screenshots_test.dart`에서만 override한다.
final cameraBackdropProvider = Provider<Widget?>((ref) => null);
