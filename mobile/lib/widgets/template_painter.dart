import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/silhouette_template.dart';
import 'guide_stroke.dart';

/// 상황별 실루엣 템플릿: 인물 윤곽선 + 보조선(발끝·테이블·지평선·다리).
/// 크기가 바뀌면 [SilhouetteTemplate.layout]으로 위치·크기를 다시 계산한다.
class TemplatePainter extends CustomPainter {
  const TemplatePainter({
    required this.template,
    required this.color,
    this.strokeWidth = 2,
    this.showLabels = true,
    this.showFigure = true,
    this.showGuides = true,
  });

  final SilhouetteTemplate template;
  final Color color;
  final double strokeWidth;
  final bool showLabels;

  /// 인물 윤곽 / 보조선 표시 여부
  final bool showFigure;
  final bool showGuides;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = template.layout(size);
    for (final guide in showGuides ? template.guides : const <GuideLine>[]) {
      final points = [for (final p in guide.points) layout.point(p)];
      final path = Path()..addPolygon(points, false);
      GuideStroke.draw(
        canvas,
        path,
        color: color.withValues(
          alpha: color.a * (guide.style == GuideLineStyle.bold ? 1 : 0.7),
        ),
        width: guide.style == GuideLineStyle.bold
            ? strokeWidth * 1.4
            : strokeWidth * 0.6,
        dashed: guide.style != GuideLineStyle.bold,
      );
      final label = guide.label;
      if (showLabels && label != null) _label(canvas, size, points, label);
    }
    if (!showFigure) return;
    GuideStroke.draw(
      canvas,
      GuideStroke.smooth([
        for (final p in template.outline) layout.figure(p),
      ], closed: template.closed),
      color: color,
      width: strokeWidth,
    );
  }

  void _label(Canvas canvas, Size size, List<Offset> points, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          shadows: const [Shadow(color: AppTheme.ink, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // 가로선은 오른쪽 끝 위, 대각선은 가운데 위
    final horizontal = (points.first.dy - points.last.dy).abs() < 1;
    final at = horizontal
        ? Offset(size.width - tp.width - 10, points.first.dy - tp.height - 3)
        : Offset.lerp(points.first, points.last, 0.5)! +
              Offset(-tp.width / 2, -tp.height - 8);
    // 다른 선과 겹쳐도 읽히도록 글자 뒤에만 작은 판
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at & tp.size).inflate(3),
        const Radius.circular(4),
      ),
      Paint()..color = AppTheme.scrim,
    );
    tp
      ..paint(canvas, at)
      ..dispose();
  }

  @override
  bool shouldRepaint(TemplatePainter old) =>
      old.template != template ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.showLabels != showLabels ||
      old.showFigure != showFigure ||
      old.showGuides != showGuides;
}
