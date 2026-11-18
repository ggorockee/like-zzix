import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/preset.dart';

/// 프리셋 공급원. 현재는 앱 번들 기본 프리셋만 사용 (서버 연동은 고도화 단계).
class PresetRepository {
  PresetRepository([AssetBundle? bundle]) : _bundle = bundle ?? rootBundle;

  static const bundledAsset = 'assets/presets/presets.json';

  final AssetBundle _bundle;

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
