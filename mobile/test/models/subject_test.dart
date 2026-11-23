import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/angle_state.dart';
import 'package:likezzix/models/coach.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/services/preset_repository.dart';

const finder = Size(360, 480);
const focal = 480.0;

/// 전신 인물 관절 (머리끝 [top] ~ 발끝 [bottom], 0~1)
List<PoseLandmark> standing(
  double top,
  double bottom, {
  double x = 0.5,
  bool feet = true,
}) {
  final h = bottom - top;
  final pts = {
    0: (0.0, 0.07),
    11: (0.09, 0.185),
    12: (-0.09, 0.185),
    23: (0.05, 0.48),
    24: (-0.05, 0.48),
    27: (0.05, 0.95),
    28: (-0.05, 0.95),
    31: (0.06, 0.99),
    32: (-0.06, 0.99),
  };
  return [
    for (var i = 0; i < PoseIndex.count; i++)
      if (pts[i] case (final dx, final dy)?)
        PoseLandmark(x + dx * h, top + dy * h, !feet && i >= 27 ? 0.1 : 0.95)
      else
        const PoseLandmark(0, 0, 0),
  ];
}

void main() {
  final templates = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );
  final full = SubjectTarget.of(
    templates.firstWhere((t) => t.id == 'tpl-full-body'),
    finder,
  )!;
  // 전신 템플릿: 머리끝 0.125, 발끝 0.917
  const top = 0.125, bottom = 0.925;

  SubjectFit fit(
    List<PoseLandmark>? lm, {
    Set<BodyAnchor> previous = const {},
  }) => SubjectFit.evaluate(
    Subject.fromLandmarks(lm, finder),
    full,
    focal: focal,
    previousHits: previous,
  );

  group('Subject.fromLandmarks', () {
    test('정수리는 코~어깨 거리로 추정', () {
      final s = Subject.fromLandmarks(standing(0.2, 0.8), finder)!;
      expect(s[BodyAnchor.head]!.dy, closeTo(0.2 * 480, 5));
      expect(s[BodyAnchor.feet]!.dy, closeTo((0.2 + 0.6 * 0.99) * 480, 1));
    });

    test('머리가 안 보이면 인물 없음, 발이 화면 밖이면 발 없음', () {
      expect(Subject.fromLandmarks(null, finder), isNull);
      expect(
        Subject.fromLandmarks(
          standing(0.2, 1.2),
          finder,
        )!.points.containsKey(BodyAnchor.feet),
        isFalse,
      );
    });
  });

  group('SubjectFit (전신)', () {
    test('사람이 없으면 0점 — 각도와 무관하게 초록불이 켜질 수 없다', () {
      expect(fit(null).action, CoachAction.findPerson);
      expect(fit(null).score, 0);
    });

    test('목표 자리에 서면 90점 이상, 모든 기준점 일치', () {
      final f = fit(standing(top, bottom));
      expect(f.score, greaterThanOrEqualTo(90));
      expect(f.action, CoachAction.hold);
      expect(f.hits, containsAll([BodyAnchor.head, BodyAnchor.feet]));
    });

    test('너무 크면 뒤로, 작으면 앞으로 + 걸음 수', () {
      final near = fit(standing(0.02, 0.99));
      expect(near.action, CoachAction.stepBack);
      final far = fit(standing(0.4, 0.8)); // 절반 크기 = 거리 2배
      expect(far.action, CoachAction.stepCloser);
      expect(far.scale, closeTo(0.5, 0.03));
      // 목표 거리 = 1.65m x 480 / (0.8 x 480) ≈ 2.1m → 2.1m 앞으로 ≈ 3걸음
      expect(far.steps, 3);
    });

    test('발이 잘리면 뒤로 가라고 안내', () {
      expect(fit(standing(0.1, 1.3)).action, CoachAction.showFeet);
      expect(
        fit(standing(top, bottom, feet: false)).action,
        CoachAction.showFeet,
      );
    });

    test('머리가 잘리면 안내', () {
      expect(fit(standing(-0.15, 0.7)).action, CoachAction.showHead);
    });

    test('좌우·높이 안내', () {
      expect(fit(standing(top, bottom, x: 0.7)).action, CoachAction.panRight);
      expect(fit(standing(top, bottom, x: 0.3)).action, CoachAction.panLeft);
      expect(
        fit(standing(top + 0.06, bottom + 0.06)).action,
        CoachAction.lowerPhone,
      );
      expect(
        fit(standing(top - 0.08, bottom - 0.08)).action,
        CoachAction.raisePhone,
      );
    });

    test('발끝만 맞으면 발끝만 반응', () {
      // 발끝 위치는 같고 키가 작은 상태
      final f = fit(standing(0.4, bottom));
      expect(f.hits, contains(BodyAnchor.feet));
      expect(f.hits, isNot(contains(BodyAnchor.head)));
    });

    test('이미 맞은 기준점은 1.5배까지 유지 (깜빡임 방지)', () {
      final moved = standing(top, bottom + 0.06);
      expect(fit(moved).hits, isNot(contains(BodyAnchor.feet)));
      expect(
        fit(moved, previous: {BodyAnchor.feet}).hits,
        contains(BodyAnchor.feet),
      );
    });
  });

  test('모든 템플릿과 사진 프리셋에서 목표 인물을 만들 수 있다', () {
    final photos = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    );
    for (final p in [...templates, ...photos]) {
      for (final size in const [
        Size(360, 480),
        Size(360, 640),
        Size(360, 360),
      ]) {
        final t = SubjectTarget.of(p, size);
        expect(t, isNotNull, reason: p.id);
        expect(t!.spanPx, greaterThan(20), reason: p.id);
        expect(t.subject[BodyAnchor.head]!.dy, greaterThan(0), reason: p.id);
        expect(SubjectTarget.of(p.flipped, size), isNotNull);
      }
    }
  });

  group('CoachMessage', () {
    AngleGuide angle({double error = 0, bool upright = true}) => AngleGuide(
      state: !upright
          ? AngleState.waiting
          : error == 0
          ? AngleState.good
          : AngleState.off,
      pitchDelta: error,
      rollDelta: 0,
      pitchError: error,
      upright: upright,
    );
    String? say(SubjectFit? f, AngleGuide a, {bool ready = false}) =>
        CoachMessage.of(angle: a, fit: f, ready: ready)?.text;
    SubjectFit doing(CoachAction a, [int steps = 0]) =>
        SubjectFit(action: a, score: 50, steps: steps);

    test('행동으로 안내', () {
      expect(say(doing(CoachAction.stepBack, 2), angle()), '뒤로 두 걸음');
      expect(say(doing(CoachAction.stepBack), angle()), '조금만 뒤로 가세요');
      expect(say(doing(CoachAction.stepCloser, 1), angle()), '앞으로 한 걸음');
      expect(say(SubjectFit.none, angle()), '사람을 화면에 담아 주세요');
    });

    test('거리 먼저, 그다음 폰 각도, 그다음 좌우·높이', () {
      expect(say(doing(CoachAction.stepBack, 1), angle(error: 8)), '뒤로 한 걸음');
      expect(say(doing(CoachAction.hold), angle(error: 8)), '폰을 살짝 들어 주세요');
      expect(say(doing(CoachAction.hold), angle(error: -8)), '폰을 살짝 숙여 주세요');
      expect(say(doing(CoachAction.panLeft), angle(error: 8)), '폰을 살짝 들어 주세요');
      expect(say(doing(CoachAction.panLeft), angle()), '폰을 왼쪽으로 살짝');
    });

    test('완성이 최우선, 폰을 눕히면 세우라고', () {
      expect(
        say(doing(CoachAction.hold), angle(), ready: true),
        '완벽해요! 지금 찍으세요',
      );
      expect(
        say(doing(CoachAction.stepBack), angle(upright: false)),
        '폰을 세워서 들어 주세요',
      );
    });

    test('프리셋을 고르기 전에는 수평 안내만', () {
      expect(say(null, angle()), isNull);
      expect(say(null, angle(error: 5)), '폰을 살짝 들어 주세요');
    });
  });
}
