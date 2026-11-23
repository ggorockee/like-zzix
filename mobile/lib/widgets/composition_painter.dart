import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/composition.dart';
import '../models/composition_fit.dart';
import '../models/subject.dart';
import 'guide_stroke.dart';

/// 벡터 구도를 그리는 공통 함수. 좌표는 0~1이고 [Size]만 곱하므로 어느 화면 비율에서도
/// 위치가 다시 계산된다. 모든 선은 [GuideStroke]의 이중 외곽선(색 선 + 어두운 그림자).
abstract final class CompositionPainter {
  static void elements(
    Canvas canvas,
    Size size,
    CompositionTemplate template, {
    required Color color,
    Color? gazeColor,
    double width = 1.6,
    bool labels = true,
  }) {
    Offset px(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    for (final e in template.elements) {
      final c = e.isGaze ? gazeColor ?? color : color;
      final w = width * e.weight;
      switch (e.type) {
        case GuideElementType.line:
          final path = Path()
            ..addPolygon([for (final p in e.points) px(p)], false);
          GuideStroke.draw(canvas, path, color: c, width: w, dashed: e.dashed);
        case GuideElementType.rect:
          final r = Rect.fromPoints(px(e.rect.topLeft), px(e.rect.bottomRight));
          GuideStroke.draw(
            canvas,
            Path()..addRect(r),
            color: c,
            width: w,
            dashed: e.dashed,
          );
        case GuideElementType.arrow:
          _arrow(canvas, px(e.points.first), px(e.points.last), c, w, e.dashed);
        case GuideElementType.grid:
          final path = Path();
          for (var i = 1; i < e.cols; i++) {
            path
              ..moveTo(size.width * i / e.cols, 0)
              ..lineTo(size.width * i / e.cols, size.height);
          }
          for (var i = 1; i < e.rows; i++) {
            path
              ..moveTo(0, size.height * i / e.rows)
              ..lineTo(size.width, size.height * i / e.rows);
          }
          GuideStroke.draw(canvas, path, color: c, width: w);
      }
      if (labels && e.label != null) _elementLabel(canvas, size, e, c, px);
    }
  }

  static void _arrow(
    Canvas canvas,
    Offset from,
    Offset to,
    Color color,
    double width,
    bool dashed,
  ) {
    final angle = (to - from).direction;
    final head = width * 6;
    Offset wing(double a) =>
        to - Offset(math.cos(angle + a), math.sin(angle + a)) * head;
    GuideStroke.draw(
      canvas,
      Path()
        ..moveTo(from.dx, from.dy)
        ..lineTo(to.dx, to.dy),
      color: color,
      width: width,
      dashed: dashed,
    );
    GuideStroke.draw(
      canvas,
      Path()..addPolygon([wing(0.5), to, wing(-0.5)], false),
      color: color,
      width: width,
    );
  }

  static void _elementLabel(
    Canvas canvas,
    Size size,
    GuideElement e,
    Color color,
    Offset Function(Offset) px,
  ) {
    switch (e.type) {
      case GuideElementType.rect:
        text(
          canvas,
          e.label!,
          px(e.rect.topCenter) + const Offset(0, 4),
          color,
        );
      case GuideElementType.line when e.points.first.dy == e.points.last.dy:
        text(
          canvas,
          e.label!,
          Offset(size.width - 8, px(e.points.first).dy + 4),
          color,
          align: 1,
        );
      default:
        text(
          canvas,
          e.label!,
          Offset.lerp(px(e.points.first), px(e.points.last), 0.5)! +
              const Offset(0, -18),
          color,
        );
    }
  }

  /// [align] 0.5는 가운데, 1은 오른쪽 정렬. 글자 뒤에만 작은 판을 깔아 어디서나 읽힌다.
  static void text(
    Canvas canvas,
    String value,
    Offset anchor,
    Color color, {
    double align = 0.5,
    double fontSize = 11,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final at = anchor - Offset(tp.width * align, 0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (at & tp.size).inflate(3),
        const Radius.circular(4),
      ),
      Paint()..color = AppTheme.ink.withValues(alpha: color.a * 0.5),
    );
    tp
      ..paint(canvas, at)
      ..dispose();
  }

  /// 얼굴 자리의 사람 모양 (머리 + 어깨). 얼굴 높이 [face] 기준.
  static void bust(Canvas canvas, Offset center, double face, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: face * 0.82, height: face),
      paint,
    );
    final top = center.dy + face * 0.62;
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(
          center.dx - face,
          top,
          center.dx + face,
          top + face * 1.7,
        ),
        topLeft: Radius.circular(face * 0.7),
        topRight: Radius.circular(face * 0.7),
        bottomLeft: Radius.circular(face * 0.15),
        bottomRight: Radius.circular(face * 0.15),
      ),
      paint,
    );
  }

  /// 전신 자리의 사람 모양 (머리끝 ~ 바닥).
  static void figure(Canvas canvas, Rect box, Paint paint) {
    final h = box.height;
    final head = h * 0.13;
    final cx = box.center.dx;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, box.top + head / 2),
        width: head * 0.82,
        height: head,
      ),
      paint,
    );
    final w = h * 0.13;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - w, box.top + head * 1.15, cx + w, box.bottom),
        Radius.circular(w * 0.8),
      ),
      paint,
    );
  }

  /// 구도 안의 사람들을 그린다 (카드 도식·일러스트 공용).
  static void people(
    Canvas canvas,
    Size size,
    CompositionTemplate template,
    Paint paint,
  ) {
    for (final s in template.subjects) {
      switch (s) {
        case FaceSpec():
          final t = FaceTarget.of(s, size);
          bust(canvas, t.center, t.size, paint);
        case BodySpec():
          final t = BodyTarget.of(s, size);
          if (s.span == BodyAnchor.feet) {
            figure(canvas, t.box, paint);
          } else {
            bust(
              canvas,
              t.head + Offset(0, t.size * 0.16),
              t.size * 0.32,
              paint,
            );
          }
      }
    }
  }
}
