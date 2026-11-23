import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 카메라 프리뷰를 화면 전체에 꽉 채움 (cover, 넘치는 부분은 잘림).
class CameraPreviewFullscreen extends StatelessWidget {
  const CameraPreviewFullscreen({super.key, required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize;
    if (!controller.value.isInitialized || previewSize == null) {
      return const ColoredBox(color: AppTheme.ink);
    }
    // previewSize는 센서 기준(가로). 세로 화면에서는 가로·세로를 바꿔 배치.
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewSize.height,
            height: previewSize.width,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}
