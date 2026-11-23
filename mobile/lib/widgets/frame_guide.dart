import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import 'silhouette_painter.dart';

/// 레퍼런스 사진 비율의 촬영 프레임: 모서리 표시 + 3분할 격자.
class FrameGuidePainter extends CustomPainter {
  const FrameGuidePainter({required this.aspectRatio, this.showGrid = true});

  final double aspectRatio;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = SilhouettePainter.frameRect(size, aspectRatio);

    if (showGrid) {
      final grid = Paint()
        ..color = AppTheme.white.withValues(alpha: 0.28)
        ..strokeWidth = 1;
      for (final t in const [1 / 3, 2 / 3]) {
        final x = frame.left + frame.width * t;
        final y = frame.top + frame.height * t;
        canvas
          ..drawLine(Offset(x, frame.top), Offset(x, frame.bottom), grid)
          ..drawLine(Offset(frame.left, y), Offset(frame.right, y), grid);
      }
    }

    final corner = Paint()
      ..color = AppTheme.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final len = frame.shortestSide * 0.08;
    for (final (p, dx, dy) in [
      (frame.topLeft, 1.0, 1.0),
      (frame.topRight, -1.0, 1.0),
      (frame.bottomLeft, 1.0, -1.0),
      (frame.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(p, p + Offset(len * dx, 0), corner)
        ..drawLine(p, p + Offset(0, len * dy), corner);
    }
  }

  @override
  bool shouldRepaint(FrameGuidePainter old) =>
      old.aspectRatio != aspectRatio || old.showGrid != showGrid;
}
