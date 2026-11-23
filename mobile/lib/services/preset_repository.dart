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

  /// 벡터 구도와 사진 목록(서버 또는 번들)을 합친다.
  ///
  /// - 같은 id(`cmp-…`)면 구도에 글·사진·순서를 입힌다
  /// - 사진 관리 대상 구도([CompositionTemplate.hasPhoto])가 목록에서 빠지면 숨긴다
  ///   (관리자 콘솔에서 비공개로 바꾼 것). 목록에 구도가 하나도 없으면 옛 서버이므로 그대로 둔다.
  /// - 구도가 아닌 항목은 사진 프리셋으로 뒤에 붙인다
  static List<Preset> merge(List<Preset> templates, List<Preset> photos) {
    final ids = {for (final t in templates) t.id};
    final byId = {for (final p in photos) p.id: p};
    final managed = byId.keys.any(ids.contains);
    final merged = [
      for (final t in templates)
        if (byId[t.id] case final doc?)
          t.withContent(doc)
        else if (!managed || !(t.template?.hasPhoto ?? false))
          t,
      for (final p in photos)
        if (!ids.contains(p.id)) p,
    ];
    final order = {for (final (i, p) in merged.indexed) p: i};
    return merged..sort((a, b) {
      final by = a.sortOrder.compareTo(b.sortOrder);
      return by != 0 ? by : order[a]!.compareTo(order[b]!);
    });
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
