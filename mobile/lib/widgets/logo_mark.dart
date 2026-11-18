import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 라익찍스 로고: 촬영 프레임 모서리 + 인물 실루엣 + 반짝임(완벽한 순간).
///
/// 앱 아이콘 PNG 생성(`tool/generate_branding.dart`), 네이티브 스플래시,
/// 로딩 화면이 모두 이 페인터 하나를 사용한다.
class LogoMarkPainter extends CustomPainter {
  const LogoMarkPainter({
    this.background = LogoBackground.gradient,
    this.markColor = Colors.white,
    this.sparkleColor = sparkleYellow,
    this.contentScale = 1,
  });

  static const gradientStart = Color(0xFFFF5A7A);
  static const gradientEnd = Color(0xFFFF9A5A);
  static const splashColor = Color(0xFFFF6E72);
  static const sparkleYellow = Color(0xFFFFE066);

  final LogoBackground background;
  final Color markColor;
  final Color sparkleColor;

  /// 마크(프레임·인물·반짝임)의 크기 비율. 안드로이드 적응형 아이콘 안전 영역용.
  final double contentScale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size(s, s);

    switch (background) {
      case LogoBackground.gradient:
        canvas.drawRect(rect, _gradientPaint(rect));
      case LogoBackground.roundedGradient:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(s * 0.23)),
          _gradientPaint(rect),
        );
      case LogoBackground.none:
        break;
    }

    canvas
      ..save()
      ..translate(s / 2, s / 2)
      ..scale(contentScale)
      ..translate(-s / 2, -s / 2);
    _paintMark(canvas, s);
    canvas.restore();
  }

  static Paint _gradientPaint(Rect rect) =>
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ).createShader(rect);

  void _paintMark(Canvas canvas, double s) {
    // 1) 촬영 프레임 모서리
    final bracket = Paint()
      ..color = markColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const lo = 0.2;
    const hi = 0.8;
    const len = 0.15;
    for (final (x, y, dx, dy) in [
      (lo, lo, 1.0, 1.0),
      (hi, lo, -1.0, 1.0),
      (lo, hi, 1.0, -1.0),
      (hi, hi, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo((x + len * dx) * s, y * s)
          ..lineTo(x * s, y * s)
          ..lineTo(x * s, (y + len * dy) * s),
        bracket,
      );
    }

    // 2) 인물 (머리 + 어깨)
    final body = Paint()..color = markColor;
    canvas.drawCircle(Offset(0.5 * s, 0.44 * s), 0.088 * s, body);
    canvas.drawPath(
      Path()
        ..moveTo(0.315 * s, 0.705 * s)
        ..cubicTo(0.315 * s, 0.6 * s, 0.4 * s, 0.555 * s, 0.5 * s, 0.555 * s)
        ..cubicTo(0.6 * s, 0.555 * s, 0.685 * s, 0.6 * s, 0.685 * s, 0.705 * s)
        ..close(),
      body,
    );

    // 3) 반짝임 (4갈래 별)
    _sparkle(canvas, Offset(0.675 * s, 0.33 * s), 0.07 * s);
  }

  void _sparkle(Canvas canvas, Offset c, double r) {
    final path = Path();
    for (var i = 0; i < 4; i++) {
      final outer = i * math.pi / 2 - math.pi / 2;
      final inner = outer + math.pi / 4;
      final o = c + Offset(math.cos(outer), math.sin(outer)) * r;
      final n = c + Offset(math.cos(inner), math.sin(inner)) * r * 0.28;
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
      path.lineTo(n.dx, n.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = sparkleColor);
  }

  @override
  bool shouldRepaint(LogoMarkPainter old) =>
      old.background != background ||
      old.markColor != markColor ||
      old.sparkleColor != sparkleColor ||
      old.contentScale != contentScale;
}

enum LogoBackground { gradient, roundedGradient, none }

/// 위젯용 로고.
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.size = 120,
    this.background = LogoBackground.roundedGradient,
  });

  final double size;
  final LogoBackground background;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: LogoMarkPainter(background: background),
  );
}
