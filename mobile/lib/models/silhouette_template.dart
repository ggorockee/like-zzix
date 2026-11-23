import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'subject.dart';

enum GuideLineStyle { thin, bold, dashed }

/// 안내선의 점. frame = 뷰파인더 기준 0~1, figure = 그림 기준(높이 1, x는 몸 중심 0).
@immutable
class GuidePoint {
  const GuidePoint(this.offset, {required this.inFigure});

  factory GuidePoint.fromJson(Map<String, dynamic> json) => GuidePoint(
    Offset((json['x'] as num).toDouble(), (json['y'] as num).toDouble()),
    inFigure: json['space'] == 'figure',
  );

  final Offset offset;
  final bool inFigure;
}

/// 발끝선·테이블 경계·지평선·다리 방향 같은 보조선.
@immutable
class GuideLine {
  const GuideLine({required this.style, required this.points, this.label});

  factory GuideLine.fromJson(Map<String, dynamic> json) => GuideLine(
    style: GuideLineStyle.values.byName(json['style'] as String? ?? 'thin'),
    label: json['label'] as String?,
    points: [
      for (final p in json['points'] as List<dynamic>)
        GuidePoint.fromJson(p as Map<String, dynamic>),
    ],
  );

  final GuideLineStyle style;
  final String? label;
  final List<GuidePoint> points;
}

/// 상황별 실루엣. 좌표가 화면 비율과 무관해 어느 비율에서도 찌그러지지 않는다.
@immutable
class SilhouetteTemplate {
  const SilhouetteTemplate({
    required this.height,
    required this.anchor,
    required this.outline,
    required this.closed,
    required this.joints,
    required this.span,
    this.guides = const [],
  });

  factory SilhouetteTemplate.fromJson(Map<String, dynamic> json) {
    final figure = json['figure'] as Map<String, dynamic>;
    final anchor = figure['anchor'] as List<dynamic>;
    return SilhouetteTemplate(
      height: (figure['height'] as num).toDouble(),
      anchor: Offset(
        (anchor[0] as num).toDouble(),
        (anchor[1] as num).toDouble(),
      ),
      closed: figure['closed'] as bool? ?? true,
      joints: {
        for (final e in (figure['joints'] as Map<String, dynamic>).entries)
          BodyAnchor.values.byName(e.key): Offset(
            ((e.value as List<dynamic>)[0] as num).toDouble(),
            ((e.value as List<dynamic>)[1] as num).toDouble(),
          ),
      },
      span: BodyAnchor.values.byName(figure['span'] as String),
      outline: [
        for (final p in figure['outline'] as List<dynamic>)
          Offset(
            ((p as List<dynamic>)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ),
      ],
      guides: [
        for (final g in json['guides'] as List<dynamic>? ?? const [])
          GuideLine.fromJson(g as Map<String, dynamic>),
      ],
    );
  }

  /// 뷰파인더 높이에 대한 그림 높이 비율
  final double height;

  /// 그림 바닥 중앙이 놓일 자리 (뷰파인더 0~1)
  final Offset anchor;

  /// 윤곽 (figure 좌표). [closed]가 false면 열린 선.
  final List<Offset> outline;
  final bool closed;

  /// 실시간 인물과 비교할 기준점 (figure 좌표)
  final Map<BodyAnchor, Offset> joints;

  /// 머리끝과 함께 인물 크기를 재는 기준점
  final BodyAnchor span;

  /// 그림 좌우 반폭 (figure 좌표)
  double get halfWidth =>
      outline.fold<double>(0.01, (m, p) => math.max(m, p.dx.abs()));

  final List<GuideLine> guides;

  /// 그림이 좌우로 넘치지 않게 하는 최대 폭 비율
  static const _maxWidth = 0.96;

  TemplateLayout layout(Size frame) {
    final scale = math.min(
      frame.height * height,
      frame.width * _maxWidth / (halfWidth * 2),
    );
    return TemplateLayout(
      frame: frame,
      base: Offset(anchor.dx * frame.width, anchor.dy * frame.height),
      scale: scale,
    );
  }

  SilhouetteTemplate get mirrored => SilhouetteTemplate(
    height: height,
    anchor: Offset(1 - anchor.dx, anchor.dy),
    closed: closed,
    joints: {
      for (final e in joints.entries) e.key: Offset(-e.value.dx, e.value.dy),
    },
    span: span,
    outline: [for (final p in outline) Offset(-p.dx, p.dy)],
    guides: [
      for (final g in guides)
        GuideLine(
          style: g.style,
          label: g.label,
          points: [
            for (final p in g.points)
              GuidePoint(
                Offset(
                  p.inFigure ? -p.offset.dx : 1 - p.offset.dx,
                  p.offset.dy,
                ),
                inFigure: p.inFigure,
              ),
          ],
        ),
    ],
  );
}

/// 특정 뷰파인더 크기에 놓인 실루엣.
@immutable
class TemplateLayout {
  const TemplateLayout({
    required this.frame,
    required this.base,
    required this.scale,
  });

  final Size frame;

  /// 그림 바닥 중앙의 화면 위치
  final Offset base;

  /// 그림 높이 1의 화면 길이 (가로·세로 같은 배율)
  final double scale;

  Offset figure(Offset p) => base + Offset(p.dx, p.dy - 1) * scale;

  Offset point(GuidePoint p) => p.inFigure
      ? figure(p.offset)
      : Offset(p.offset.dx * frame.width, p.offset.dy * frame.height);
}
