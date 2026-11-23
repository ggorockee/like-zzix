import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/services/preset_repository.dart';

void main() {
  test('번들 사진: 모두 33점·가이드·사진 포함, sort_order 정렬', () {
    final presets = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    );
    expect(presets, hasLength(12));
    for (final p in presets) {
      expect(p.landmarks, hasLength(PoseIndex.count), reason: p.id);
      expect(p.title, isNotEmpty);
      expect(p.guide, isNotEmpty, reason: p.id);
      expect(p.referenceAsset, 'assets/presets/reference/${p.id}.jpg');
      expect(File(p.referenceAsset!).existsSync(), isTrue, reason: p.id);
    }
    final orders = presets.map((p) => p.sortOrder).toList();
    expect(orders, [...orders]..sort());
    expect(presets.map((p) => p.id).toSet(), hasLength(presets.length));
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
    expect(presets.single.category, PresetCategory.special);
    expect(presets.single.guide, isEmpty);
  });
}
