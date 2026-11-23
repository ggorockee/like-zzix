import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'angle_spec.dart';
import 'silhouette_template.dart';

/// 프리셋 카테고리. `id`는 서버/번들 JSON의 `category` 값.
enum PresetCategory {
  fullBody('full_body', '전신샷'),
  lookBack('look_back', '부르고 찍기'),
  side('side', '옆모습'),
  cafe('cafe', '음료·카페'),
  landscape('landscape', '풍경'),
  sitting('sitting', '앉은 포즈');

  const PresetCategory(this.id, this.label);

  final String id;
  final String label;

  static PresetCategory? tryParse(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// BlazePose 랜드마크 1개. x·y는 프레임 기준 0~1 정규화 (화면 밖은 범위를 벗어날 수 있음).
@immutable
class PoseLandmark {
  const PoseLandmark(this.x, this.y, this.likelihood);

  factory PoseLandmark.fromJson(List<dynamic> json) => PoseLandmark(
    (json[0] as num).toDouble(),
    (json[1] as num).toDouble(),
    (json[2] as num).toDouble(),
  );

  final double x;
  final double y;
  final double likelihood;

  bool get isVisible => likelihood >= 0.5;
}

/// BlazePose 33점 인덱스 중 실루엣/매칭에 쓰는 것.
abstract final class PoseIndex {
  static const nose = 0;
  static const leftShoulder = 11;
  static const rightShoulder = 12;
  static const leftElbow = 13;
  static const rightElbow = 14;
  static const leftWrist = 15;
  static const rightWrist = 16;
  static const leftHip = 23;
  static const rightHip = 24;
  static const leftKnee = 25;
  static const rightKnee = 26;
  static const leftAnkle = 27;
  static const rightAnkle = 28;
  static const count = 33;

  /// 좌우를 바꾼 관절 번호 (코만 짝이 없음)
  static int mirrorOf(int i) => switch (i) {
    0 => 0,
    >= 1 && <= 3 => i + 3,
    >= 4 && <= 6 => i - 3,
    _ => i.isOdd ? i + 1 : i - 1,
  };
}

/// 구도 프리셋. 두 종류가 있다.
/// - 실루엣 템플릿([template] 있음): 상황별 기본 구도
/// - 사진 프리셋: 레퍼런스 사진 (`01_MOBILE.md` 5장 스키마)
///
/// 둘 다 목표 인물 자리([SubjectTarget])와 권장 각도([angle])만 뽑아 실시간 인물과 비교한다.
@immutable
class Preset {
  const Preset({
    required this.id,
    required this.category,
    required this.title,
    required this.tip,
    required this.aspectRatio,
    required this.angle,
    required this.sortOrder,
    this.landmarks = const [],
    this.template,
    this.mirrored = false,
    this.guide = const [],
    this.outline = const [],
    this.referenceAsset,
    this.referenceUrl,
  });

  factory Preset.fromJson(Map<String, dynamic> json) {
    final camera = json['camera'] as Map<String, dynamic>? ?? const {};
    final pose = json['pose'] as Map<String, dynamic>;
    final landmarks = (pose['landmarks'] as List<dynamic>)
        .map((e) => PoseLandmark.fromJson(e as List<dynamic>))
        .toList(growable: false);
    if (landmarks.length != PoseIndex.count) {
      throw FormatException('landmarks must be 33, got ${landmarks.length}');
    }
    return Preset(
      id: json['id'] as String,
      category:
          PresetCategory.tryParse(json['category'] as String?) ??
          PresetCategory.fullBody,
      title: json['title'] as String,
      tip: json['tip'] as String? ?? '',
      aspectRatio: _parseAspectRatio(json['aspect_ratio'] as String?),
      angle: AngleSpec.target(
        pitchDeg: (camera['pitch_deg'] as num?)?.toDouble() ?? 0,
        rollDeg: (camera['roll_deg'] as num?)?.toDouble() ?? 0,
      ),
      landmarks: landmarks,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      guide: [
        for (final step in json['guide'] as List<dynamic>? ?? const [])
          step as String,
      ],
      outline: [
        for (final p in json['outline'] as List<dynamic>? ?? const [])
          Offset(
            ((p as List<dynamic>)[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ),
      ],
      referenceAsset: json['reference_asset'] as String?,
      referenceUrl: json['reference_url'] as String?,
    );
  }

  /// 실루엣 템플릿 (`assets/templates/templates.json`)
  factory Preset.fromTemplateJson(Map<String, dynamic> json, int order) =>
      Preset(
        id: json['id'] as String,
        category:
            PresetCategory.tryParse(json['category'] as String?) ??
            PresetCategory.fullBody,
        title: json['title'] as String,
        tip: json['tip'] as String? ?? '',
        aspectRatio: 3 / 4,
        angle: AngleSpec.fromJson(json['angle'] as Map<String, dynamic>),
        sortOrder: order,
        guide: [
          for (final step in json['guide'] as List<dynamic>? ?? const [])
            step as String,
        ],
        template: SilhouetteTemplate.fromJson(json),
      );

  final String id;
  final PresetCategory category;
  final String title;
  final String tip;

  /// 가로/세로 비율 (예: "3:4" → 0.75)
  final double aspectRatio;

  /// 권장 촬영 각도
  final AngleSpec angle;

  /// 레퍼런스 관절. 실루엣 템플릿은 비어 있음.
  final List<PoseLandmark> landmarks;

  /// 선 실루엣 (사진 프리셋은 null)
  final SilhouetteTemplate? template;

  /// 좌우 반전된 상태인지
  final bool mirrored;
  final int sortOrder;

  /// 이 구도대로 찍기 위한 단계별 안내.
  final List<String> guide;

  /// 사람 윤곽선 (프레임 기준 0~1 좌표, 시계방향 폐곡선). 없으면 관절로 실루엣을 그림.
  final List<Offset> outline;

  /// 레퍼런스 사진 asset 경로. 로컬 빌드에만 존재할 수 있으므로 없을 때를 처리해야 함.
  final String? referenceAsset;

  /// 관리자 콘솔에서 올린 레퍼런스 사진 경로 (서버 기준 상대 경로, 예: /v1/presets/{id}/image?v=...).
  final String? referenceUrl;

  bool get isTemplate => template != null;

  bool get hasLandmarks => landmarks.length >= PoseIndex.count;

  /// 좌우를 뒤집은 프리셋 (다시 부르면 원래대로).
  Preset get flipped => Preset(
    id: id,
    category: category,
    title: title,
    tip: tip,
    aspectRatio: aspectRatio,
    angle: angle,
    sortOrder: sortOrder,
    guide: guide,
    landmarks: [
      if (hasLandmarks)
        for (var i = 0; i < PoseIndex.count; i++)
          () {
            final l = landmarks[PoseIndex.mirrorOf(i)];
            return PoseLandmark(1 - l.x, l.y, l.likelihood);
          }(),
    ],
    outline: [for (final p in outline) Offset(1 - p.dx, p.dy)],
    referenceAsset: referenceAsset,
    referenceUrl: referenceUrl,
    template: template?.mirrored,
    mirrored: !mirrored,
  );

  bool get hasOutline => outline.length >= 3;

  static double _parseAspectRatio(String? value) {
    final parts = value?.split(':');
    if (parts == null || parts.length != 2) return 3 / 4;
    final w = double.tryParse(parts[0]);
    final h = double.tryParse(parts[1]);
    if (w == null || h == null || w <= 0 || h <= 0) return 3 / 4;
    return w / h;
  }

  @override
  bool operator ==(Object other) =>
      other is Preset && other.id == id && other.mirrored == mirrored;

  @override
  int get hashCode => Object.hash(id, mirrored);
}
