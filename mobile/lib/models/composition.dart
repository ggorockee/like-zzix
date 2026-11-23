import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'subject.dart';

/// 벡터 구도 템플릿 (`assets/templates/compositions.json`).
///
/// 좌표는 모두 뷰파인더 기준 0.0~1.0. 화면 비율이 바뀌면 뷰파인더 크기만 다시 곱한다.
/// - [elements]: 화면에 그리는 선·상자·화살표·격자
/// - [subjects]: 인물이 들어올 자리와 판정 조건 (1명 이상)
@immutable
class CompositionTemplate {
  const CompositionTemplate({
    required this.elements,
    required this.subjects,
    this.scene = 'plain',
    this.example,
  });

  factory CompositionTemplate.fromJson(Map<String, dynamic> json) {
    final subjects = [
      for (final s in json['subjects'] as List<dynamic>)
        SubjectSpec.fromJson(s as Map<String, dynamic>),
    ];
    if (subjects.isEmpty) throw const FormatException('subjects is empty');
    return CompositionTemplate(
      elements: [
        for (final e in json['elements'] as List<dynamic>? ?? const [])
          GuideElement.fromJson(e as Map<String, dynamic>),
      ],
      subjects: subjects,
      scene: json['scene'] as String? ?? 'plain',
      example: json['example'] as String?,
    );
  }

  final List<GuideElement> elements;
  final List<SubjectSpec> subjects;

  /// 예시 사진이 없을 때 그리는 일러스트 배경
  final String scene;

  /// 예시 사진 asset
  final String? example;

  CompositionTemplate get mirrored => CompositionTemplate(
    elements: [for (final e in elements) e.mirrored],
    subjects: [for (final s in subjects) s.mirrored],
    scene: scene,
    example: example,
  );
}

Offset _mirror(Offset p) => Offset(1 - p.dx, p.dy);

Offset _point(dynamic json) {
  final p = json as List<dynamic>;
  return Offset((p[0] as num).toDouble(), (p[1] as num).toDouble());
}

enum GuideElementType { line, rect, arrow, grid }

@immutable
class GuideElement {
  const GuideElement({
    required this.type,
    this.points = const [],
    this.rect = Rect.zero,
    this.cols = 3,
    this.rows = 3,
    this.dashed = false,
    this.weight = 1,
    this.label,
    this.isGaze = false,
  });

  factory GuideElement.fromJson(Map<String, dynamic> json) {
    final rect = json['rect'] as List<dynamic>?;
    return GuideElement(
      type: GuideElementType.values.byName(json['type'] as String),
      points: [
        for (final p in json['points'] as List<dynamic>? ?? const []) _point(p),
      ],
      rect: rect == null
          ? Rect.zero
          : Rect.fromLTWH(
              (rect[0] as num).toDouble(),
              (rect[1] as num).toDouble(),
              (rect[2] as num).toDouble(),
              (rect[3] as num).toDouble(),
            ),
      cols: (json['cols'] as num?)?.toInt() ?? 3,
      rows: (json['rows'] as num?)?.toInt() ?? 3,
      dashed: json['style'] == 'dashed',
      weight: (json['weight'] as num?)?.toDouble() ?? 1,
      label: json['label'] as String?,
      isGaze: json['role'] == 'gaze',
    );
  }

  final GuideElementType type;
  final List<Offset> points;
  final Rect rect;
  final int cols;
  final int rows;
  final bool dashed;

  /// 선 굵기 배율
  final double weight;
  final String? label;

  /// 시선 화살표: 얼굴이 이 방향을 보면 초록으로 바뀐다
  final bool isGaze;

  GuideElement get mirrored => GuideElement(
    type: type,
    points: [for (final p in points) _mirror(p)],
    rect: Rect.fromLTWH(1 - rect.right, rect.top, rect.width, rect.height),
    cols: cols,
    rows: rows,
    dashed: dashed,
    weight: weight,
    label: label,
    isGaze: isGaze,
  );
}

enum Gaze {
  left,
  right;

  Gaze get flipped => this == left ? right : left;
}

/// 인물 한 명이 들어올 자리.
@immutable
sealed class SubjectSpec {
  const SubjectSpec({this.label});

  factory SubjectSpec.fromJson(Map<String, dynamic> json) {
    final label = json['label'] as String?;
    switch (json['detect']) {
      case 'face':
        final size = json['size'] as List<dynamic>;
        final min = (size[0] as num).toDouble();
        final max = (size[1] as num).toDouble();
        if (min <= 0 || max <= min) throw const FormatException('size');
        return FaceSpec(
          anchor: _point(json['anchor']),
          radius: (json['radius'] as num?)?.toDouble() ?? 0.06,
          sizeMin: min,
          sizeMax: max,
          gaze: switch (json['gaze']) {
            final String g => Gaze.values.byName(g),
            _ => null,
          },
          label: label,
        );
      case 'body':
        return BodySpec(
          head: _point(json['head']),
          bottom: _point(json['bottom']),
          span: BodyAnchor.values.byName(json['span'] as String? ?? 'feet'),
          label: label,
        );
      default:
        throw FormatException('unknown detect: ${json['detect']}');
    }
  }

  /// 2인 이상일 때 구분하는 이름 (앞·뒤 등)
  final String? label;

  SubjectSpec get mirrored;
}

/// 얼굴 인식으로 판정하는 자리.
@immutable
class FaceSpec extends SubjectSpec {
  const FaceSpec({
    required this.anchor,
    required this.radius,
    required this.sizeMin,
    required this.sizeMax,
    this.gaze,
    super.label,
  });

  /// 얼굴 중심이 들어올 점
  final Offset anchor;

  /// 허용 반경 (뷰파인더 높이 대비)
  final double radius;

  /// 얼굴 상자 높이 범위 (뷰파인더 높이 대비)
  final double sizeMin;
  final double sizeMax;

  /// 바라볼 방향 (화면 기준)
  final Gaze? gaze;

  @override
  FaceSpec get mirrored => FaceSpec(
    anchor: _mirror(anchor),
    radius: radius,
    sizeMin: sizeMin,
    sizeMax: sizeMax,
    gaze: gaze?.flipped,
    label: label,
  );
}

/// 포즈 인식으로 판정하는 자리 (머리끝과 [span]의 위치).
@immutable
class BodySpec extends SubjectSpec {
  const BodySpec({
    required this.head,
    required this.bottom,
    required this.span,
    super.label,
  });

  final Offset head;
  final Offset bottom;
  final BodyAnchor span;

  @override
  BodySpec get mirrored => BodySpec(
    head: _mirror(head),
    bottom: _mirror(bottom),
    span: span,
    label: label,
  );
}
