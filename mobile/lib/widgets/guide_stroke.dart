import 'dart:ui';

import '../core/app_theme.dart';

/// 밝은 하늘에서도 어두운 실내에서도 보이는 가이드 선: 얇은 색 선 + 얇은 어두운 외곽 그림자.
/// 면은 채우지 않는다.
abstract final class GuideStroke {
  static void draw(
    Canvas canvas,
    Path path, {
    required Color color,
    double width = 2,
    bool dashed = false,
  }) {
    final line = dashed ? dash(path) : path;
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(
        line,
        stroke(AppTheme.ink.withValues(alpha: color.a * 0.75), width + 2.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
      )
      ..drawPath(line, stroke(color, width));
  }

  static Path dash(Path path, {double on = 9, double off = 7}) {
    final out = Path();
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += on + off) {
        out.addPath(m.extractPath(d, d + on), Offset.zero);
      }
    }
    return out;
  }

  /// Catmull-Rom 스플라인을 3차 베지어로 변환한 부드러운 경로.
  static Path smooth(List<Offset> pts, {required bool closed}) {
    final path = Path();
    if (pts.length < 2) return path;
    final n = pts.length;
    Offset at(int i) => closed ? pts[(i % n + n) % n] : pts[i.clamp(0, n - 1)];
    path.moveTo(pts[0].dx, pts[0].dy);
    final segments = closed ? n : n - 1;
    for (var i = 0; i < segments; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final p2 = at(i + 1);
      final p3 = at(i + 2);
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    if (closed) path.close();
    return path;
  }
}
