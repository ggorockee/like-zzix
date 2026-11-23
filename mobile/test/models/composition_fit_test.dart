import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/angle_state.dart';
import 'package:likezzix/models/coach.dart';
import 'package:likezzix/models/composition_fit.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/services/preset_repository.dart';

const finder = Size(360, 480);
const focal = 480.0;

List<PoseLandmark> standing(
  double top,
  double bottom, {
  double x = 0.5,
  bool feet = true,
}) {
  final h = bottom - top;
  const pts = {
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
  final presets = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );
  List<Target> targets(String id) =>
      Target.of(presets.firstWhere((p) => p.id == id), finder);

  LivePerson face(
    Target t, {
    Offset shift = Offset.zero,
    double scale = 1,
    double? yaw,
  }) => LivePerson.face(
    Rect.fromCenter(
      center: t.center + shift,
      width: t.size * 0.8 * scale,
      height: t.size * scale,
    ),
    yawDeg: yaw,
  );

  CompositionFit fit(List<Target> t, List<LivePerson> people) =>
      CompositionFit.evaluate(t, people, focal: focal);

  group('얼굴 구도', () {
    final t = targets('cmp-thirds');

    test('사람이 없으면 0점 — 각도와 무관하게 초록불이 켜질 수 없다', () {
      final f = fit(t, const []);
      expect(f.score, 0);
      expect(f.action, CoachAction.findPerson);
      expect(f.hasEveryone, isFalse);
    });

    test('점 위에 알맞은 크기면 100점, 반경·크기 경계에서 90점', () {
      expect(fit(t, [face(t.single)]).score, closeTo(100, 1e-6));
      final radius = (t.single as FaceTarget).radius;
      expect(
        fit(t, [face(t.single, shift: Offset(radius, 0))]).score,
        closeTo(90, 1e-6),
      );
      expect(
        fit(t, [face(t.single, shift: Offset(radius * 1.1, 0))]).score,
        lessThan(90),
      );
      final edge = (t.single as FaceTarget).sizeMax / t.single.size;
      expect(fit(t, [face(t.single, scale: edge)]).score, closeTo(90, 1e-6));
    });

    test('크기 힌트와 걸음 수', () {
      expect(fit(t, [face(t.single, scale: 1.8)]).action, CoachAction.stepBack);
      final far = fit(t, [face(t.single, scale: 0.4)]);
      expect(far.action, CoachAction.stepCloser);
      expect(far.steps, greaterThan(1));
    });

    test('위치 힌트', () {
      CoachAction at(Offset o) => fit(t, [face(t.single, shift: o)]).action;
      expect(at(const Offset(60, 0)), CoachAction.panRight);
      expect(at(const Offset(-60, 0)), CoachAction.panLeft);
      expect(at(const Offset(0, 60)), CoachAction.lowerPhone);
      expect(at(const Offset(0, -60)), CoachAction.raisePhone);
    });

    test('지나가는 사람보다 자리에 맞는 사람을 고른다', () {
      final passerby = LivePerson.face(const Rect.fromLTWH(20, 200, 16, 20));
      final f = fit(t, [passerby, face(t.single)]);
      expect(f.score, closeTo(100, 1e-6));
    });

    test('이미 맞은 조건은 1.4배까지 유지', () {
      final radius = (t.single as FaceTarget).radius;
      final live = face(t.single, shift: Offset(radius * 1.2, 0));
      expect(
        t.single.evaluate(live, const {}).hits,
        isNot(contains(GuidePart.position)),
      );
      expect(
        t.single.evaluate(live, {GuidePart.position}).hits,
        contains(GuidePart.position),
      );
    });
  });

  group('시선 앞 여백 (headEulerAngleY)', () {
    final t = targets('cmp-gaze-room');

    test('화살표(왼쪽)를 보면 통과, 정면·반대면 시선 안내', () {
      expect(
        fit(t, [face(t.single, yaw: -25)]).score,
        greaterThanOrEqualTo(90),
      );
      for (final yaw in [0.0, 20.0, -8.0]) {
        final f = fit(t, [face(t.single, yaw: yaw)]);
        expect(f.score, lessThan(90), reason: '$yaw');
        expect(f.action, CoachAction.lookLeft, reason: '$yaw');
      }
    });

    test('각도를 모르면 통과하지 않는다', () {
      expect(fit(t, [face(t.single)]).score, lessThan(90));
    });

    test('반전하면 오른쪽', () {
      final m = Target.of(
        presets.firstWhere((p) => p.id == 'cmp-gaze-room').flipped,
        finder,
      );
      expect(fit(m, [face(m.single, yaw: 25)]).score, greaterThanOrEqualTo(90));
      expect(fit(m, [face(m.single, yaw: -25)]).action, CoachAction.lookRight);
    });
  });

  group('2인 구도', () {
    final t = targets('cmp-two-height');

    test('두 얼굴이 각 자리에 있으면 통과 (순서 무관)', () {
      expect(fit(t, [face(t[1]), face(t[0])]).score, closeTo(100, 1e-6));
    });

    test('한 명뿐이면 두 사람이 보이게', () {
      final f = fit(t, [face(t[0])]);
      expect(f.action, CoachAction.findSecond);
      expect(f.score, 0);
    });

    test('둘 다 같은 쪽으로 어긋나면 폰을, 한 사람만이면 그 사람을', () {
      const s = Offset(60, 0);
      expect(
        fit(t, [face(t[0], shift: s), face(t[1], shift: s)]).action,
        CoachAction.panRight,
      );
      final one = fit(t, [
        face(t[0], shift: const Offset(0, 50)),
        face(t[1], shift: const Offset(0, -50)),
      ]);
      expect(one.action, anyOf(CoachAction.personUp, CoachAction.personDown));
      expect(one.who, isNotNull);
    });

    test('한 사람만 크면 그 사람이 뒤로', () {
      final f = fit(t, [face(t[0], scale: 2), face(t[1], scale: 0.95)]);
      expect(f.action, CoachAction.personBack);
      expect(f.who, '낮게 분');
    });
  });

  group('전신 구도 (포즈)', () {
    final t = targets('cmp-full-body');
    CompositionFit body(List<PoseLandmark> lm) {
      final b = BodyPoints.fromLandmarks(lm, finder);
      return fit(t, [if (b != null) LivePerson.body(b, BodyAnchor.feet)]);
    }

    test('자리에 서면 90점 이상, 머리·발끝 반응', () {
      final f = body(standing(0.125, 0.925));
      expect(f.score, greaterThanOrEqualTo(90));
      expect(
        f.targets.single.hits,
        containsAll([GuidePart.head, GuidePart.bottom]),
      );
    });

    test('크면 뒤로, 절반 크기면 앞으로 세 걸음', () {
      expect(body(standing(0.02, 0.99)).action, CoachAction.stepBack);
      final far = body(standing(0.4, 0.8));
      expect(far.action, CoachAction.stepCloser);
      expect(far.steps, 3);
    });

    test('발·머리가 잘리면 안내', () {
      expect(body(standing(0.1, 1.3)).action, CoachAction.showFeet);
      expect(body(standing(-0.15, 0.7)).action, CoachAction.showHead);
    });

    test('발끝만 맞으면 발끝만 반응', () {
      final hits = body(standing(0.4, 0.925)).targets.single.hits;
      expect(hits, {GuidePart.bottom});
    });

    test('얼굴만 있고 포즈가 없으면 사람 없음', () {
      expect(fit(t, [face(t.single)]).action, CoachAction.findPerson);
    });
  });

  test('사진 프리셋도 인물 자리를 만든다', () {
    final photos = PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    );
    for (final p in photos) {
      expect(Target.of(p, finder), hasLength(1), reason: p.id);
      expect(Target.of(p.flipped, finder), hasLength(1));
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
    String? say(
      CoachAction a,
      AngleGuide g, {
      int steps = 0,
      String? who,
      bool ready = false,
    }) => CoachMessage.of(
      angle: g,
      fit: CompositionFit(targets: const [], action: a, steps: steps, who: who),
      ready: ready,
    )?.text;

    test('행동으로 안내', () {
      expect(say(CoachAction.stepBack, angle(), steps: 2), '뒤로 두 걸음');
      expect(say(CoachAction.stepCloser, angle()), '조금만 앞으로 가세요');
      expect(say(CoachAction.lookLeft, angle()), '얼굴을 화살표(왼쪽) 쪽으로');
      expect(say(CoachAction.personUp, angle(), who: '왼쪽 분'), '왼쪽 분, 조금 더 높게');
    });

    test('거리 → 폰 각도 → 위치 → 시선 순', () {
      final off = angle(error: 8);
      expect(say(CoachAction.stepBack, off, steps: 1), '뒤로 한 걸음');
      for (final a in [
        CoachAction.panLeft,
        CoachAction.lookLeft,
        CoachAction.hold,
      ]) {
        expect(say(a, off), '폰을 살짝 들어 주세요');
      }
      expect(say(CoachAction.hold, angle(error: -8)), '폰을 살짝 숙여 주세요');
    });

    test('완성이 최우선, 눕히면 세우라고', () {
      expect(say(CoachAction.hold, angle(), ready: true), '완벽해요! 지금 찍으세요');
      expect(say(CoachAction.stepBack, angle(upright: false)), '폰을 세워서 들어 주세요');
    });
  });
}
