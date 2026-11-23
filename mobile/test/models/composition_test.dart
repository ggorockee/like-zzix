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
    expect(presets.length, 23);
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
      expect(t.center.dy / finder.height, closeTo(0.36, 1e-3));
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

  test('구도표의 19종(실루엣 제외)이 모두 있다', () {
    expect(
      presets.map((p) => p.id),
      containsAll([
        for (final id in [
          'center', 'thirds', 'symmetry', 'negative-space', 'gaze-room', //
          'frame', 'circle', 'ascending', 'descending', 'triangle', 's-pose',
          'leading', 'vanishing', 'pattern', 'foreground', 'two-height',
          'two-depth', 'mirror', 'tight',
        ])
          'cmp-$id',
      ]),
    );
    expect(presets.map((p) => p.title), isNot(contains('실루엣')));
  });

  group('사진 병합', () {
    final bundled = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    );
    Preset find(List<Preset> list, String id) =>
        list.firstWhere((p) => p.id == id);

    test('번들 사진 12장이 모두 구도와 짝이 맞고 파일이 있다', () {
      expect(bundled.length, 12);
      final managed = presets.where((p) => p.template!.hasPhoto);
      expect(
        bundled.map((p) => p.id).toSet(),
        managed.map((p) => p.id).toSet(),
      );
      for (final p in bundled) {
        expect(File(p.referenceAsset!).existsSync(), isTrue, reason: p.id);
        // 관리자 카테고리와 앱 탭이 같은 곳을 가리킨다
        expect(p.category, find(presets, p.id).category, reason: p.id);
      }
    });

    test('구도는 그대로, 글·사진·순서만 입힌다', () {
      final merged = PresetRepository.merge(presets, bundled);
      final center = find(merged, 'cmp-center');
      expect(center.template, same(find(presets, 'cmp-center').template));
      expect(center.angle.elevationMax, 5);
      expect(center.hasPhoto, isTrue);
      expect(merged.first.id, 'cmp-center');
      // 사진 있는 구도가 앞, 없는 구도가 뒤
      expect(merged.take(12).every((p) => p.hasPhoto), isTrue);
      expect(merged.length, 23);
    });

    test('관리자가 비공개로 바꾼 구도는 숨긴다', () {
      final merged = PresetRepository.merge(presets, [
        for (final p in bundled)
          if (p.id != 'cmp-mirror') p,
      ]);
      expect(merged.map((p) => p.id), isNot(contains('cmp-mirror')));
      expect(merged.map((p) => p.id), contains('cmp-negative-space'));
    });

    test('구도가 없는 옛 서버 목록이면 숨기지 않고, 사진 프리셋은 함께 보인다', () {
      final old = PresetRepository.parse(
        File(PresetRepository.bundledAsset)
            .readAsStringSync()
            .replaceAll('"id": "cmp-', '"id": "old-'),
      );
      final merged = PresetRepository.merge(presets, old);
      expect(merged.map((p) => p.id), contains('cmp-mirror'));
      expect(merged.map((p) => p.id), contains('old-mirror'));
    });

    test('사진 없던 구도도 관리자에 같은 id로 올리면 사진이 붙는다', () {
      final doc = PresetRepository.parse(
        File(PresetRepository.bundledAsset)
            .readAsStringSync()
            .replaceAll('cmp-center', 'cmp-frame'),
      ).firstWhere((p) => p.id == 'cmp-frame');
      final merged = PresetRepository.merge(presets, [...bundled, doc]);
      expect(find(merged, 'cmp-frame').hasPhoto, isTrue);
    });

    test('반전해도 사진 경로를 유지한다', () {
      final p = find(PresetRepository.merge(presets, bundled), 'cmp-thirds');
      expect(p.flipped.referenceAsset, p.referenceAsset);
    });
  });
}
