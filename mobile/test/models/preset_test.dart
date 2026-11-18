import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/services/preset_repository.dart';

void main() {
  test('번들 프리셋: 모두 33점·윤곽선·가이드 포함, sort_order 정렬', () {
    final raw = File(PresetRepository.bundledAsset).readAsStringSync();
    final presets = PresetRepository.parse(raw);

    expect(presets.length, greaterThanOrEqualTo(4));
    for (final p in presets) {
      expect(p.landmarks, hasLength(PoseIndex.count), reason: p.id);
      expect(p.title, isNotEmpty);
      expect(p.hasOutline, isTrue, reason: p.id);
      expect(p.guide, isNotEmpty, reason: p.id);
      expect(p.referenceAsset, startsWith('assets/presets/reference/'));
      for (final o in p.outline) {
        expect(o.dx, inInclusiveRange(0, 1), reason: p.id);
        expect(o.dy, inInclusiveRange(0, 1), reason: p.id);
      }
    }
    final orders = presets.map((p) => p.sortOrder).toList();
    expect(orders, [...orders]..sort());
    expect(presets.map((p) => p.id).toSet(), hasLength(presets.length));
  });

  test('번들 프리셋: 모든 카테고리가 최소 1개', () {
    final presets = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    );
    expect(
      presets.map((p) => p.category).toSet(),
      PresetCategory.values.toSet(),
    );
  });

  test('랜드마크 수가 33이 아닌 항목은 건너뜀', () {
    final landmarks = List.filled(33, '[0.5,0.5,0.9]').join(',');
    final raw =
        '''
{"items":[
 {"id":"bad","category":"full_body","title":"x","pose":{"landmarks":[[0,0,1]]}},
 {"id":"ok","category":"side","title":"y","aspect_ratio":"4:5","sort_order":1,
  "pose":{"landmarks":[$landmarks]}}
]}''';
    final presets = PresetRepository.parse(raw);
    expect(presets.map((p) => p.id), ['ok']);
    expect(presets.single.aspectRatio, closeTo(0.8, 1e-9));
    expect(presets.single.category, PresetCategory.side);
    expect(presets.single.hasOutline, isFalse);
    expect(presets.single.guide, isEmpty);
  });
}
