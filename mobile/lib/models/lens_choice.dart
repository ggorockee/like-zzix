import 'package:camera/camera.dart';

import 'zoom_range.dart';

/// 배율에 맞는 카메라 고르기.
///
/// Android는 기본 카메라의 줌이 0.5배(초광각)까지 이어지지만, iOS는 초광각이 별도 카메라다.
abstract final class LensChoice {
  /// 방향이 같은 기본(광각) 카메라. 초광각·망원은 피한다.
  static CameraDescription? main(
    List<CameraDescription> cameras,
    CameraLensDirection lens,
  ) {
    final same = cameras.where((c) => c.lensDirection == lens);
    return same
            .where(
              (c) =>
                  c.lensType != CameraLensType.ultraWide &&
                  c.lensType != CameraLensType.telephoto,
            )
            .firstOrNull ??
        same.firstOrNull;
  }

  /// 기본 카메라 줌([mainRange])이 1배부터 시작할 때만 쓰는 별도 초광각 카메라.
  static CameraDescription? ultraWide(
    List<CameraDescription> cameras,
    CameraLensDirection lens,
    ZoomRange mainRange,
  ) => mainRange.min < 1
      ? null
      : cameras
            .where(
              (c) =>
                  c.lensDirection == lens &&
                  c.lensType == CameraLensType.ultraWide,
            )
            .firstOrNull;

  /// 초광각 카메라의 1배는 기본 카메라 기준 0.5배
  static double deviceZoom(double zoom, {required bool onUltraWide}) =>
      onUltraWide ? zoom / ZoomRange.appMin : zoom;
}
