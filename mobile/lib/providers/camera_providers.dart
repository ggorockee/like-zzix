import 'package:camera/camera.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/capture_service.dart';

/// 기기의 카메라 목록 (시뮬레이터 등에서는 빈 목록).
final availableCamerasProvider = FutureProvider<List<CameraDescription>>(
  (ref) => availableCameras(),
);

final captureServiceProvider = Provider<CaptureService>(
  (ref) => CaptureService(),
);
