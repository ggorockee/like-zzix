import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/preset.dart';
import 'guide_stroke.dart';

/// 프리셋 실루엣을 그린다.
///
/// - 윤곽선([Preset.outline])이 있으면: 부드러운 곡선 + 어두운 외곽 그림자
/// - 없으면: 관절로 만든 볼륨형 마네킹 실루엣
///
/// 좌표는 프리셋 비율 프레임 기준 0~1이므로, 캔버스 안에 그 비율의 사각형을
/// 가운데 맞춤으로 잡고([frameRect]) 그 안에 그린다.
class SilhouettePainter extends CustomPainter {
  const SilhouettePainter({
    required this.preset,
    required this.color,
    this.strokeWidth = 3,
    this.fillOpacity = 0.12,
  });

  final Preset preset;
  final Color color;
  final double strokeWidth;
  final double fillOpacity;

  /// [size] 안에서 [aspectRatio](가로/세로) 프레임이 차지하는 영역.
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
    final frame = frameRect(size, preset.aspectRatio);
    if (preset.hasOutline) {
      _paintOutline(canvas, frame);
    } else if (preset.landmarks.length >= PoseIndex.count) {
      _paintMannequin(canvas, frame);
    }
  }

  // ---------------------------------------------------------------------------
  // 윤곽선
  // ---------------------------------------------------------------------------

  void _paintOutline(Canvas canvas, Rect frame) {
    final points = [
      for (final p in preset.outline)
        Offset(
          frame.left + p.dx * frame.width,
          frame.top + p.dy * frame.height,
        ),
    ];

    // 채움은 폐곡선 전체로
    if (fillOpacity > 0) {
      canvas.drawPath(
        GuideStroke.smooth(points, closed: true),
        Paint()..color = color.withValues(alpha: fillOpacity),
      );
    }

    // 선은 사진 가장자리/캡션에 잘린 직선 구간을 빼고 그림
    final stroke = Path();
    for (final run in _visibleRuns(preset.outline)) {
      stroke.addPath(
        GuideStroke.smooth([for (final i in run) points[i]], closed: false),
        Offset.zero,
      );
    }
    GuideStroke.draw(canvas, stroke, color: color, width: strokeWidth);
  }

  /// 잘린 경계(이미지 테두리 또는 가장 아래쪽의 수평 직선)를 제외한 연속 구간들.
  /// 반환값은 [outline] 인덱스 목록의 목록.
  static List<List<int>> _visibleRuns(List<Offset> outline) {
    final n = outline.length;
    final maxY = outline.map((p) => p.dy).reduce(math.max);
    bool isCut(int i) {
      final a = outline[i];
      final b = outline[(i + 1) % n];
      bool onBorder(Offset p) =>
          p.dx <= 0.003 || p.dx >= 0.997 || p.dy <= 0.003 || p.dy >= 0.997;
      final bottomCut =
          a.dy >= maxY - 0.015 &&
          b.dy >= maxY - 0.015 &&
          (a.dx - b.dx).abs() > (a.dy - b.dy).abs() * 4;
      return (onBorder(a) && onBorder(b)) || bottomCut;
    }

    final cuts = [for (var i = 0; i < n; i++) isCut(i)];
    if (!cuts.contains(true)) {
      return [
        [for (var i = 0; i <= n; i++) i % n],
      ];
    }
    // 잘린 구간 바로 다음 점에서 시작해 한 바퀴 돌며 구간을 나눈다.
    final start = (cuts.indexOf(true) + 1) % n;
    final runs = <List<int>>[];
    var current = <int>[start];
    for (var k = 0; k < n; k++) {
      final i = (start + k) % n;
      if (cuts[i]) {
        if (current.length > 1) runs.add(current);
        current = [(i + 1) % n];
      } else {
        current.add((i + 1) % n);
      }
    }
    if (current.length > 1) runs.add(current);
    return runs;
  }

  // ---------------------------------------------------------------------------
  // 관절 기반 마네킹 (윤곽선이 없는 프리셋용)
  // ---------------------------------------------------------------------------

  static const _limbs = [
    (PoseIndex.leftShoulder, PoseIndex.leftElbow, 0.20),
    (PoseIndex.leftElbow, PoseIndex.leftWrist, 0.17),
    (PoseIndex.rightShoulder, PoseIndex.rightElbow, 0.20),
    (PoseIndex.rightElbow, PoseIndex.rightWrist, 0.17),
    (PoseIndex.leftHip, PoseIndex.leftKnee, 0.30),
    (PoseIndex.leftKnee, PoseIndex.leftAnkle, 0.24),
    (PoseIndex.rightHip, PoseIndex.rightKnee, 0.30),
    (PoseIndex.rightKnee, PoseIndex.rightAnkle, 0.24),
  ];

  void _paintMannequin(Canvas canvas, Rect frame) {
    final lm = preset.landmarks;
    Offset at(int i) => Offset(
      frame.left + lm[i].x * frame.width,
      frame.top + lm[i].y * frame.height,
    );
    bool visible(int i) => lm[i].isVisible;

    final shoulderWidth =
        visible(PoseIndex.leftShoulder) && visible(PoseIndex.rightShoulder)
        ? (at(PoseIndex.leftShoulder) - at(PoseIndex.rightShoulder)).distance
        : frame.width * 0.2;

    // 겹치는 부위의 투명도가 진해지지 않도록 한 레이어에 그린 뒤 합성
    final body = Path();
    for (final (a, b, thickness) in _limbs) {
      if (!visible(a) || !visible(b)) continue;
      body.addPath(
        _capsule(at(a), at(b), shoulderWidth * thickness / 2),
        Offset.zero,
      );
    }
    final torso = [
      PoseIndex.leftShoulder,
      PoseIndex.rightShoulder,
      PoseIndex.rightHip,
      PoseIndex.leftHip,
    ];
    if (torso.every(visible)) {
      body.addPolygon([for (final i in torso) at(i)], true);
    }
    if (visible(PoseIndex.nose)) {
      body.addOval(
        Rect.fromCircle(
          center: at(PoseIndex.nose),
          radius: math.max(shoulderWidth * 0.3, frame.width * 0.03),
        ),
      );
    }

    canvas.saveLayer(frame.inflate(frame.width), Paint());
    canvas.drawPath(body, Paint()..color = color.withValues(alpha: 0.35));
    canvas.restore();
  }

  static Path _capsule(Offset a, Offset b, double radius) {
    final d = b - a;
    final len = d.distance;
    if (len == 0) {
      return Path()..addOval(Rect.fromCircle(center: a, radius: radius));
    }
    final angle = math.atan2(d.dy, d.dx);
    final rect = Rect.fromLTWH(-radius, -radius, len + radius * 2, radius * 2);
    final matrix = Matrix4.identity()
      ..translateByDouble(a.dx, a.dy, 0, 1)
      ..rotateZ(angle);
    return (Path()
          ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))))
        .transform(matrix.storage);
  }

  @override
  bool shouldRepaint(SilhouettePainter old) =>
      old.preset != preset ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.fillOpacity != fillOpacity;
}
