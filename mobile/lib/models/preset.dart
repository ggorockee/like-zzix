import 'package:flutter/foundation.dart';

import 'angle_spec.dart';
import 'composition.dart';

/// 구도 목록의 탭. 서버·관리자 콘솔은 옛 카테고리 id(full_body 등)를 그대로 쓴다.
enum PresetCategory {
  basic('기본/인물', ['basic', 'full_body']),
  travel('배경/여행', ['travel', 'cafe']),
  pose('포즈/느낌', ['pose', 'look_back']),
  special('특수/2인', ['special', 'side']);

  const PresetCategory(this.label, this.ids);

  final String label;
  final List<String> ids;

  static PresetCategory? tryParse(String? id) {
    for (final c in values) {
      if (c.ids.contains(id)) return c;
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

/// BlazePose 33점 인덱스 중 인물 자리에 쓰는 것.
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
/// - 벡터 구도([template] 있음): 선·앵커로 된 기본 구도
/// - 사진 프리셋: 레퍼런스 사진 (`01_MOBILE.md` 5장 스키마)
///
/// 둘 다 인물 자리(`Target`)와 권장 각도([angle])만 뽑아 실시간 인물과 비교한다.
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
          PresetCategory.basic,
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
      referenceAsset: json['reference_asset'] as String?,
      referenceUrl: json['reference_url'] as String?,
    );
  }

  /// 벡터 구도 (`assets/templates/compositions.json`)
  factory Preset.fromTemplateJson(Map<String, dynamic> json, int order) =>
      Preset(
        id: json['id'] as String,
        category:
            PresetCategory.tryParse(json['category'] as String?) ??
            PresetCategory.basic,
        title: json['title'] as String,
        tip: json['tip'] as String? ?? '',
        aspectRatio: 3 / 4,
        angle: AngleSpec.fromJson(json['angle'] as Map<String, dynamic>),
        sortOrder: 1000 + order,
        guide: [
          for (final step in json['guide'] as List<dynamic>? ?? const [])
            step as String,
        ],
        template: CompositionTemplate.fromJson(json),
      );

  final String id;
  final PresetCategory category;
  final String title;
  final String tip;

  /// 가로/세로 비율 (예: "3:4" → 0.75)
  final double aspectRatio;

  /// 권장 촬영 각도
  final AngleSpec angle;

  /// 레퍼런스 관절. 벡터 구도는 비어 있음.
  final List<PoseLandmark> landmarks;

  /// 벡터 구도 (사진 프리셋은 null)
  final CompositionTemplate? template;

  /// 좌우 반전된 상태인지
  final bool mirrored;
  final int sortOrder;

  /// 이 구도대로 찍기 위한 단계별 안내.
  final List<String> guide;

  /// 레퍼런스 사진 asset 경로. 로컬 빌드에만 존재할 수 있으므로 없을 때를 처리해야 함.
  final String? referenceAsset;

  /// 관리자 콘솔에서 올린 레퍼런스 사진 경로 (서버 기준 상대 경로, 예: /v1/presets/{id}/image?v=...).
  final String? referenceUrl;

  bool get isTemplate => template != null;

  bool get hasLandmarks => landmarks.length >= PoseIndex.count;

  /// 벡터 구도에 [doc](관리자 콘솔 또는 번들)의 글·사진을 입힌다. 판정용 구도는 그대로.
  Preset withContent(Preset doc) => Preset(
    id: id,
    category: category,
    title: doc.title,
    tip: doc.tip.isEmpty ? tip : doc.tip,
    aspectRatio: doc.aspectRatio,
    angle: angle,
    sortOrder: doc.sortOrder,
    guide: doc.guide.isEmpty ? guide : doc.guide,
    template: template,
    referenceAsset: doc.referenceAsset ?? referenceAsset,
    referenceUrl: doc.referenceUrl,
  );

  /// 서버 사진을 못 받을 때(오프라인) 쓸 번들 사진 경로를 채운다.
  Preset withBundledPhoto(List<Preset> bundled) {
    if (referenceAsset != null) return this;
    for (final b in bundled) {
      if (b.id == id) return _withAsset(b.referenceAsset);
    }
    return this;
  }

  Preset _withAsset(String? asset) => Preset(
    id: id,
    category: category,
    title: title,
    tip: tip,
    aspectRatio: aspectRatio,
    angle: angle,
    sortOrder: sortOrder,
    guide: guide,
    landmarks: landmarks,
    referenceAsset: asset,
    referenceUrl: referenceUrl,
    template: template,
    mirrored: mirrored,
  );

  bool get hasPhoto => referenceAsset != null || referenceUrl != null;

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
    referenceAsset: referenceAsset,
    referenceUrl: referenceUrl,
    template: template?.mirrored,
    mirrored: !mirrored,
  );

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
