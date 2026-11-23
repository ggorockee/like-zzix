import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/composition_fit.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/providers/composition_providers.dart';
import 'package:likezzix/providers/shooting_providers.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/dynamic_frame.dart';

void main() {
  const finder = Size(360, 480);
  final presets = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );
  final thirds = presets.firstWhere((p) => p.id == 'cmp-thirds');

  CompositionState stateOf(Preset p, {Offset shift = Offset.zero}) {
    final targets = Target.of(p, finder);
    return CompositionState(
      targets: targets,
      fit: CompositionFit.evaluate(targets, [
        for (final t in targets)
          if (t is FaceTarget)
            LivePerson.face(t.box.shift(shift), yawDeg: 0)
          else if (t is BodyTarget)
            LivePerson.body(
              BodyPoints({
                BodyAnchor.head: t.head + shift,
                BodyAnchor.shoulders: t.head + shift,
                t.span: t.bottom + shift,
              }, halfWidth: t.halfWidth),
              t.span,
            ),
      ], focal: 480),
    );
  }

  FrameVisual run(
    FrameVisual v,
    CompositionState? s,
    ShootSignal signal,
    double seconds,
  ) {
    for (var i = 0; i < seconds * 60; i++) {
      v = v.step(s, signal, 1 / 60);
    }
    return v;
  }

  test('자석: 가까우면 자리에 붙고, 멀면 사람을 따라간다', () {
    final target = Target.of(thirds, finder).single;
    final near = run(
      const FrameVisual(),
      stateOf(thirds, shift: const Offset(10, 0)),
      ShootSignal.adjusting,
      1,
    );
    expect(near.people.single.box!.center.dx, closeTo(target.center.dx, 0.5));
    final far = run(
      const FrameVisual(),
      stateOf(thirds, shift: const Offset(-150, 0)),
      ShootSignal.adjusting,
      1,
    );
    expect(
      far.people.single.box!.center.dx,
      closeTo(target.center.dx - 150, 0.5),
    );
  });

  test('완성: 바로 초록, 0.3초 뒤 은은하게 투명, 어긋나면 다시 나타남', () {
    final s = stateOf(thirds);
    var v = run(const FrameVisual(), s, ShootSignal.ready, 0.28);
    expect(v.ready, greaterThan(0.9));
    expect(v.fade, closeTo(1, 0.01)); // 아직 선명
    v = run(v, s, ShootSignal.ready, 1.2);
    expect(v.fade, closeTo(FrameVisual.faded, 0.02));
    v = run(v, s, ShootSignal.adjusting, 0.5);
    expect(v.fade, closeTo(1, 0.02));
    expect(v.ready, lessThan(0.02));
  });

  test('조건별로 반응: 위치가 맞아도 시선이 다르면 화살표는 그대로', () {
    final gaze = presets.firstWhere((p) => p.id == 'cmp-gaze-room');
    final v = run(
      const FrameVisual(),
      stateOf(gaze),
      ShootSignal.adjusting,
      1,
    ).people.single;
    expect(v.part(GuidePart.position), closeTo(1, 0.01));
    expect(v.part(GuidePart.gaze), closeTo(0, 0.01));
  });

  test('사람이 없고 전환이 끝나면 다시 그리지 않는다', () {
    final empty = CompositionState(
      targets: Target.of(thirds, finder),
      fit: CompositionFit.none,
    );
    final v = run(const FrameVisual(), empty, ShootSignal.waiting, 1);
    expect(v.step(empty, ShootSignal.waiting, 1 / 60).isIdleAfter(v), isTrue);
    expect(
      v.step(stateOf(thirds), ShootSignal.adjusting, 1 / 60).isIdleAfter(v),
      isFalse,
    );
  });

  testWidgets('모든 구도·신호에서 오류 없이 그려진다', (tester) async {
    for (final p in presets) {
      for (final signal in ShootSignal.values) {
        await tester.pumpWidget(
          DynamicFrame(
            template: p.template,
            signal: signal,
            state: stateOf(p, shift: const Offset(20, 30)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    expect(tester.takeException(), isNull);
  });
}
