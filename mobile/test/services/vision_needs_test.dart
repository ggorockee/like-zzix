import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/services/vision_service.dart';

void main() {
  final needs = {
    for (final p in PresetRepository.parseTemplates(
      File(PresetRepository.templatesAsset).readAsStringSync(),
    ))
      p.id: VisionNeeds.of(p),
  };

  test('구도에 필요한 인식기만 켠다', () {
    expect(
      (needs['cmp-center']!.face, needs['cmp-center']!.body),
      (true, false),
    );
    expect(
      (needs['cmp-full-body']!.face, needs['cmp-full-body']!.body),
      (false, true),
    );
  });

  test('작은 얼굴이 필요한 구도에서만 최소 크기를 낮춘다', () {
    expect(needs['cmp-center']!.minFaceSize, 0.12);
    expect(needs['cmp-thirds']!.minFaceSize, 0.09);
    expect(needs['cmp-two-depth']!.minFaceSize, 0.06);
  });

  test('사진 프리셋은 포즈만', () {
    final photo = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    ).first;
    expect(VisionNeeds.of(photo).body, isTrue);
    expect(VisionNeeds.of(photo).face, isFalse);
  });
}
