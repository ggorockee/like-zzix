import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:likezzix/models/preview_transform.dart';
import 'package:likezzix/services/vision_service.dart';
import 'package:likezzix/widgets/silhouette_painter.dart';

void main() {
  group('PreviewTransform (cover)', () {
    // 360x800 화면, 720x1280 프리뷰(9:16) → 높이에 맞춰 450x800, 좌우 45씩 잘림
    const screen = Size(360, 800);
    final transform = PreviewTransform(
      screen: screen,
      previewAspect: 720 / 1280,
      frame: SilhouettePainter.frameRect(screen, 1),
    );

    test('프리뷰 영역은 화면을 꽉 채우고 좌우가 잘림', () {
      expect(transform.previewRect, const Rect.fromLTWH(-45, 0, 450, 800));
    });

    test('중앙은 프레임 중앙', () {
      final f = transform.toFrame(const Offset(0.5, 0.5));
      expect(f.dx, closeTo(0.5, 1e-9));
      expect(f.dy, closeTo(0.5, 1e-9));
    });

    test('프리뷰 왼쪽 끝은 화면 밖(프레임 기준 음수)', () {
      expect(transform.toFrame(const Offset(0, 0.5)).dx, lessThan(0));
    });
  });

  group('VisionService.normalize (ML Kit 예제 규칙)', () {
    test('Android 후면(90°): 회전된 이미지 크기로 정규화', () {
      final n = VisionService.normalize(
        const Offset(180, 960),
        imageSize: const Size(1280, 720),
        rotation: InputImageRotation.rotation90deg,
        lens: CameraLensDirection.back,
        isIOS: false,
      );
      expect(n.dx, closeTo(0.25, 1e-9));
      expect(n.dy, closeTo(0.75, 1e-9));
    });

    test('Android 전면(270°): 프리뷰처럼 좌우반전', () {
      final n = VisionService.normalize(
        const Offset(180, 960),
        imageSize: const Size(1280, 720),
        rotation: InputImageRotation.rotation270deg,
        lens: CameraLensDirection.front,
        isIOS: false,
      );
      expect(n.dx, closeTo(0.75, 1e-9));
      expect(n.dy, closeTo(0.75, 1e-9));
    });

    test('센서 방향 → 입력 회전값', () {
      expect(
        VisionService.imageRotation(sensorOrientation: 90),
        InputImageRotation.rotation90deg,
      );
      expect(
        VisionService.imageRotation(sensorOrientation: 270),
        InputImageRotation.rotation270deg,
      );
    });
  });
}
