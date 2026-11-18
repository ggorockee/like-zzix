import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/preset.dart';

/// 포즈 랜드마크로 사람 실루엣(관절 연결선 + 머리)을 그린다.
///
/// 랜드마크는 프리셋 비율([aspectRatio]) 프레임 기준 0~1 좌표이므로,
/// 캔버스 안에 그 비율의 사각형을 가운데 맞춤으로 잡고 그 안에 그린다.
class SilhouettePainter extends CustomPainter {
  const SilhouettePainter({
    required this.landmarks,
    required this.aspectRatio,
    required this.color,
    this.strokeWidth = 3,
    this.dashed = true,
  });

  final List<PoseLandmark> landmarks;
  final double aspectRatio;
  final Color color;
  final double strokeWidth;
  final bool dashed;

  static const _bones = [
    (PoseIndex.leftShoulder, PoseIndex.rightShoulder),
    (PoseIndex.leftShoulder, PoseIndex.leftElbow),
    (PoseIndex.leftElbow, PoseIndex.leftWrist),
    (PoseIndex.rightShoulder, PoseIndex.rightElbow),
    (PoseIndex.rightElbow, PoseIndex.rightWrist),
    (PoseIndex.leftShoulder, PoseIndex.leftHip),
    (PoseIndex.rightShoulder, PoseIndex.rightHip),
    (PoseIndex.leftHip, PoseIndex.rightHip),
    (PoseIndex.leftHip, PoseIndex.leftKnee),
    (PoseIndex.leftKnee, PoseIndex.leftAnkle),
    (PoseIndex.rightHip, PoseIndex.rightKnee),
    (PoseIndex.rightKnee, PoseIndex.rightAnkle),
  ];

  /// [size] 안에서 [aspectRatio] 프레임이 차지하는 영역.
  static Rect frameRect(Size size, double aspectRatio) {
    var width = size.width;
    var height = width / aspectRatio;
    if (height > size.height) {
      height = size.height;
      width = height * aspectRatio;
    }
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.length < PoseIndex.count) return;
    final frame = frameRect(size, aspectRatio);
    Offset at(int i) => Offset(
      frame.left + landmarks[i].x * frame.width,
      frame.top + landmarks[i].y * frame.height,
    );
    bool visible(int i) => landmarks[i].isVisible;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path();
    for (final (a, b) in _bones) {
      if (visible(a) && visible(b)) {
        path
          ..moveTo(at(a).dx, at(a).dy)
          ..lineTo(at(b).dx, at(b).dy);
      }
    }

    // 머리: 코 중심, 반지름은 어깨너비 기준 (어깨가 안 보이면 프레임 기준)
    if (visible(PoseIndex.nose)) {
      final nose = at(PoseIndex.nose);
      final shoulders =
          visible(PoseIndex.leftShoulder) && visible(PoseIndex.rightShoulder);
      final radius = shoulders
          ? math.max(
              (at(PoseIndex.leftShoulder) - at(PoseIndex.rightShoulder))
                      .distance *
                  0.32,
              frame.width * 0.035,
            )
          : frame.width * 0.07;
      path.addOval(Rect.fromCircle(center: nose, radius: radius));

      // 목: 머리 아래 → 어깨 중점
      if (shoulders) {
        final mid = Offset.lerp(
          at(PoseIndex.leftShoulder),
          at(PoseIndex.rightShoulder),
          0.5,
        )!;
        final dir = mid - nose;
        if (dir.distance > radius) {
          final start = nose + dir / dir.distance * radius;
          path
            ..moveTo(start.dx, start.dy)
            ..lineTo(mid.dx, mid.dy);
        }
      }
    }

    canvas.drawPath(dashed ? _dash(path, strokeWidth) : path, paint);
  }

  static Path _dash(Path source, double strokeWidth) {
    final dashLength = strokeWidth * 3;
    final gapLength = strokeWidth * 2.2;
    final result = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dashLength, metric.length);
        result.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gapLength;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(SilhouettePainter old) =>
      old.landmarks != landmarks ||
      old.aspectRatio != aspectRatio ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.dashed != dashed;
}
