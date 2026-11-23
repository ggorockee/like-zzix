import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 라익찍스 로고.
///
/// - 왼쪽 아래 "L"(Like)과 오른쪽 위 모서리가 만나 촬영 프레임이 된다.
/// - 프레임 안 인물의 머리는 민트색 점: 앱이 "구도가 맞았다"고 알려 주는 관절 점.
///
/// 앱 아이콘 PNG 생성(`tool/generate_branding.dart`), 네이티브 스플래시,
/// 로딩 화면이 모두 이 페인터 하나를 사용한다. 색은 [AppTheme]의 핵심·서브 색만 쓴다.
class LogoMarkPainter extends CustomPainter {
  const LogoMarkPainter({
    this.background = LogoBackground.square,
    this.markColor = AppTheme.white,
    this.accentColor = AppTheme.mint,
    this.contentScale = 1,
    this.paintMark = true,
  });

  final LogoBackground background;

  /// 프레임과 몸 색
  final Color markColor;

  /// 머리(일치 점) 색
  final Color accentColor;

  /// 마크의 크기 비율. 안드로이드 적응형 아이콘 안전 영역용.
  final double contentScale;

  /// false면 배경만 그린다 (적응형 아이콘 배경).
  final bool paintMark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rect = Offset.zero & Size(s, s);
    final fill = Paint()..color = AppTheme.coral;

    switch (background) {
      case LogoBackground.square:
        canvas.drawRect(rect, fill);
      case LogoBackground.rounded:
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(s * 0.23)),
          fill,
        );
      case LogoBackground.none:
        break;
    }
    if (!paintMark) return;

    canvas
      ..save()
      ..translate(s / 2, s / 2)
      ..scale(contentScale)
      ..translate(-s / 2, -s / 2);
    _paintMark(canvas, s);
    canvas.restore();
  }

  void _paintMark(Canvas canvas, double s) {
    // 1) 프레임: 왼쪽 아래 L, 오른쪽 위 모서리 (중심에 대해 점대칭)
    final frame = Paint()
      ..color = markColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.076
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const lo = 0.2;
    const hi = 0.8;
    const arm = 0.31;
    canvas
      ..drawPath(
        Path()
          ..moveTo(lo * s, (hi - arm) * s)
          ..lineTo(lo * s, hi * s)
          ..lineTo((lo + arm) * s, hi * s),
        frame,
      )
      ..drawPath(
        Path()
          ..moveTo((hi - arm) * s, lo * s)
          ..lineTo(hi * s, lo * s)
          ..lineTo(hi * s, (lo + arm) * s),
        frame,
      );

    // 2) 인물: 몸은 아래 모서리를 살짝 둥글린 반원, 머리는 일치 점
    final body = Paint()..color = markColor;
    const bodyRadius = 0.175;
    final base = Offset(0.5 * s, 0.69 * s);
    canvas
      ..drawPath(
        Path()
          ..moveTo(base.dx - bodyRadius * s, base.dy - 0.02 * s)
          ..arcTo(
            Rect.fromCircle(
              center: base.translate(0, -0.02 * s),
              radius: bodyRadius * s,
            ),
            math.pi,
            math.pi,
            false,
          )
          ..quadraticBezierTo(
            base.dx + bodyRadius * s,
            base.dy,
            base.dx + (bodyRadius - 0.022) * s,
            base.dy,
          )
          ..lineTo(base.dx - (bodyRadius - 0.022) * s, base.dy)
          ..quadraticBezierTo(
            base.dx - bodyRadius * s,
            base.dy,
            base.dx - bodyRadius * s,
            base.dy - 0.02 * s,
          )
          ..close(),
        body,
      )
      ..drawCircle(
        Offset(0.5 * s, 0.368 * s),
        0.1 * s,
        Paint()..color = accentColor,
      );
  }

  @override
  bool shouldRepaint(LogoMarkPainter old) =>
      old.background != background ||
      old.markColor != markColor ||
      old.accentColor != accentColor ||
      old.contentScale != contentScale ||
      old.paintMark != paintMark;
}

enum LogoBackground { square, rounded, none }

/// 위젯용 로고.
class LogoMark extends StatelessWidget {
  const LogoMark({
    super.key,
    this.size = 120,
    this.background = LogoBackground.rounded,
  });

  final double size;
  final LogoBackground background;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: LogoMarkPainter(background: background),
  );
}
