import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/models/silhouette_template.dart';
import 'package:likezzix/models/viewfinder_aspect.dart';
import 'package:likezzix/services/preset_repository.dart';

void main() {
  final templates = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );
  Preset of(String id) => templates.firstWhere((t) => t.id == id);

  test('4가지 템플릿과 권장 각도 (로우앵글 +)', () {
    expect(
      {
        for (final t in templates)
          t.id: (
            t.angle.elevationMin,
            t.angle.elevationMax,
            t.angle.rollTolerance,
          ),
      },
      {
        'tpl-full-body': (5, 10, 3),
        'tpl-cafe': (-10, 0, 3),
        'tpl-landscape': (-3, 3, 2),
        'tpl-sitting': (0, 5, 3),
      },
    );
    expect(templates.every((t) => t.isTemplate && !t.hasLandmarks), isTrue);
  });

  test('어느 화면 비율에서도 찌그러지지 않고 뷰파인더 안에 들어간다', () {
    for (final t in templates) {
      final template = t.template!;
      for (final a in ViewfinderAspect.values) {
        final frame = Size(360, 360 / a.ratio);
        final layout = template.layout(frame);
        // 가로·세로 배율이 같음 = 찌그러짐 없음
        final unit = layout.figure(const Offset(0.1, 0.6));
        final origin = layout.figure(const Offset(0, 0.5));
        expect(
          (unit.dx - origin.dx).abs(),
          closeTo((unit.dy - origin.dy).abs(), 1e-6),
        );
        for (final p in template.outline) {
          final s = layout.figure(p);
          expect(s.dy, inInclusiveRange(0, frame.height), reason: t.id);
          expect(s.dx, inInclusiveRange(0, frame.width), reason: '${t.id} $a');
        }
      }
    }
  });

  test('전신: 발끝이 하단 5~10% 안, 카페: 테이블 선이 하단 1/3', () {
    const frame = Size(300, 400);
    final body = of('tpl-full-body').template!;
    final feet = body.outline
        .map((p) => body.layout(frame).figure(p).dy)
        .reduce((a, b) => a > b ? a : b);
    expect(1 - feet / frame.height, inInclusiveRange(0.05, 0.10));
    final table = of('tpl-cafe').template!.guides.single.points.first;
    expect(table.offset.dy, closeTo(2 / 3, 0.01));
  });

  test('풍경: 인물이 3분할 좌측 세로선, 반전하면 우측', () {
    final t = of('tpl-landscape');
    expect(t.template!.anchor.dx, closeTo(1 / 3, 1e-6));
    expect(t.flipped.template!.anchor.dx, closeTo(2 / 3, 1e-6));
  });

  test('반전: 두 번이면 원래대로, 반전 상태는 다른 값', () {
    final t = of('tpl-sitting');
    expect(t.flipped, isNot(t));
    expect(t.flipped.flipped, t);
    expect(
      t.flipped.template!.outline.first.dx,
      closeTo(-t.template!.outline.first.dx, 1e-9),
    );
    final corner = t.flipped.template!.guides.first.points.last.offset;
    expect(corner.dx, lessThan(0.1)); // 다리 선이 왼쪽 아래 모서리로
  });

  test('사진 프리셋 반전: 좌우 관절이 서로 바뀐다', () {
    final photo = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    ).first;
    final l = photo.landmarks[PoseIndex.leftWrist];
    final r = photo.flipped.landmarks[PoseIndex.rightWrist];
    expect(r.x, closeTo(1 - l.x, 1e-9));
    expect(r.y, l.y);
    expect(
      {
        for (var i = 0; i < PoseIndex.count; i++)
          PoseIndex.mirrorOf(PoseIndex.mirrorOf(i)),
      }.length,
      PoseIndex.count,
    );
  });

  group('ViewfinderAspect.layout', () {
    const screen = Size(360, 880);
    Rect at(ViewfinderAspect a) =>
        a.layout(screen, safeTop: 30, top: 90, bottom: 250);

    test('비율 유지, 화면 안', () {
      for (final a in ViewfinderAspect.values) {
        final rect = at(a);
        expect(rect.width / rect.height, closeTo(a.ratio, 1e-6));
        expect(rect.top, greaterThanOrEqualTo(30));
        expect(rect.bottom, lessThanOrEqualTo(screen.height));
      }
    });

    test('컨트롤 사이에 맞으면 가운데', () {
      final rect = at(ViewfinderAspect.r1x1);
      expect(rect.center.dy, closeTo((90 + 630) / 2, 1e-6));
    });
  });

  test('GuideLine: 알 수 없는 좌표계는 frame으로', () {
    expect(GuidePoint.fromJson(const {'x': 0.5, 'y': 1}).inFigure, isFalse);
  });
}
