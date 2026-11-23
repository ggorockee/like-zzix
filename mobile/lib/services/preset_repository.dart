import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/preset.dart';

/// 앱 번들에 든 벡터 구도 템플릿과 사진 프리셋.
class PresetRepository {
  PresetRepository([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;

  static const bundledAsset = 'assets/presets/presets.json';

  final AssetBundle _bundle;

  static const templatesAsset = 'assets/templates/compositions.json';

  /// 벡터 구도 템플릿 (앱에 항상 포함)
  Future<List<Preset>> loadTemplates() async =>
      parseTemplates(await _bundle.loadString(templatesAsset));

  static List<Preset> parseTemplates(String raw) {
    final items =
        (jsonDecode(raw) as Map<String, dynamic>)['items'] as List<dynamic>;
    final templates = <Preset>[];
    for (final (i, item) in items.indexed) {
      try {
        templates.add(Preset.fromTemplateJson(item as Map<String, dynamic>, i));
      } on Object catch (e) {
        debugPrint('[Preset] 잘못된 템플릿 건너뜀: $e');
      }
    }
    return templates;
  }

  Future<List<Preset>> loadBundled() async {
    final raw = await _bundle.loadString(bundledAsset);
    return parse(raw);
  }

  /// 목록 응답(`{"version":..,"items":[..]}`) 파싱. 잘못된 항목은 건너뛰고 정렬.
  static List<Preset> parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final presets = <Preset>[];
    for (final item in json['items'] as List<dynamic>) {
      try {
        presets.add(Preset.fromJson(item as Map<String, dynamic>));
      } on Object catch (e) {
        debugPrint('[Preset] 잘못된 항목 건너뜀: $e');
      }
    }
    presets.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return presets;
  }
}
