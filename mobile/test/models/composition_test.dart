import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/composition.dart';
import 'package:likezzix/models/composition_fit.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/models/viewfinder_aspect.dart';
import 'package:likezzix/services/preset_repository.dart';

void main() {
  final raw = File(PresetRepository.templatesAsset).readAsStringSync();
  final presets = PresetRepository.parseTemplates(raw);
  CompositionTemplate of(String id) =>
      presets.firstWhere((p) => p.id == id).template!;

  test('모든 항목이 파싱되고 4개 탭에 고루 있다', () {
    final items = (jsonDecode(raw) as Map<String, dynamic>)['items'] as List;
    expect(presets.length, items.length);
    expect(presets.length, 12);
    for (final c in PresetCategory.values) {
      expect(
        presets.where((p) => p.category == c),
        isNotEmpty,
        reason: c.label,
      );
    }
    expect(presets.map((p) => p.id).toSet().length, presets.length);
  });

  test('좌표는 모두 0~1, 얼굴·전신 자리는 뷰파인더 안', () {
    for (final p in presets) {
      for (final e in p.template!.elements) {
        for (final q in e.points) {
          expect(q.dx, inInclusiveRange(0, 1), reason: p.id);
          expect(q.dy, inInclusiveRange(0, 1), reason: p.id);
        }
      }
      for (final a in ViewfinderAspect.values) {
        final finder = Size(360, 360 / a.ratio);
        for (final t in Target.of(p, finder)) {
          expect(
            (Offset.zero & finder).contains(t.center),
            isTrue,
            reason: '${p.id} $a',
          );
          expect(t.box.top, greaterThanOrEqualTo(0), reason: '${p.id} $a');
          expect(t.size, greaterThan(15), reason: '${p.id} $a');
        }
      }
    }
  });

  test('화면 비율이 바뀌면 같은 비율 위치로 다시 계산된다', () {
    final p = presets.firstWhere((p) => p.id == 'cmp-thirds');
    for (final a in ViewfinderAspect.values) {
      final finder = Size(360, 360 / a.ratio);
      final t = Target.of(p, finder).single;
      expect(t.center.dx / finder.width, closeTo(2 / 3, 1e-3));
      expect(t.center.dy / finder.height, closeTo(1 / 3, 1e-3));
      // 얼굴 프레임은 비율과 무관하게 찌그러지지 않는다
      expect(t.box.width / t.box.height, closeTo(0.8, 1e-9));
    }
  });

  test('필수 구도의 특징', () {
    expect(of('cmp-center').subjects.single, isA<FaceSpec>());
    expect(of('cmp-thirds').elements.single.type, GuideElementType.grid);
    expect(
      of('cmp-negative-space').elements.single.type,
      GuideElementType.rect,
    );
    expect((of('cmp-gaze-room').subjects.single as FaceSpec).gaze, Gaze.left);
    expect(of('cmp-gaze-room').elements.single.isGaze, isTrue);
    expect(of('cmp-frame').elements.single.type, GuideElementType.rect);
    expect(of('cmp-vanishing').elements.length, 5);
    expect(of('cmp-two-height').subjects.length, 2);
    expect(of('cmp-two-depth').subjects.length, 2);
  });

  test('좌우 반전: 자리·선·시선이 뒤집히고 두 번이면 원래대로', () {
    final t = of('cmp-gaze-room');
    final m = t.mirrored;
    final a = t.subjects.single as FaceSpec, b = m.subjects.single as FaceSpec;
    expect(b.anchor.dx, closeTo(1 - a.anchor.dx, 1e-9));
    expect(b.gaze, Gaze.right);
    expect(m.elements.single.points.last.dx, greaterThan(0.5));
    expect(
      (m.mirrored.subjects.single as FaceSpec).anchor.dx,
      closeTo(a.anchor.dx, 1e-9),
    );
    final space = of('cmp-negative-space');
    expect(space.elements.single.rect.left, greaterThan(0.5));
    expect(space.mirrored.elements.single.rect.right, lessThan(0.5));
  });

  test('잘못된 템플릿은 건너뛴다', () {
    expect(
      PresetRepository.parseTemplates(
        '{"items":[{"id":"a","title":"b","angle":{},"subjects":[]},'
        '{"id":"c","title":"d","angle":{},'
        '"subjects":[{"detect":"face","anchor":[0.5,0.5],"size":[0.2,0.1]}]}]}',
      ),
      isEmpty,
    );
  });

  test('예시 사진 asset이 실제로 있다', () {
    for (final p in presets) {
      final example = p.template!.example;
      if (example != null) {
        expect(File(example).existsSync(), isTrue, reason: example);
      }
    }
  });
}
