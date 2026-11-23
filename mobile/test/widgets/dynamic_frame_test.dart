import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/providers/subject_providers.dart';
import 'package:likezzix/widgets/dynamic_frame.dart';

void main() {
  const target = SubjectTarget(
    Subject({
      BodyAnchor.head: Offset(180, 60),
      BodyAnchor.feet: Offset(180, 440),
    }, halfWidth: 70),
    span: BodyAnchor.feet,
    finder: Size(360, 480),
  );
  const live = Subject({
    BodyAnchor.head: Offset(200, 80),
    BodyAnchor.feet: Offset(200, 460),
  }, halfWidth: 70);

  SubjectState state(double score, {Set<BodyAnchor> hits = const {}}) =>
      SubjectState(
        target: target,
        live: live,
        fit: SubjectFit(action: CoachAction.hold, score: score, hits: hits),
      );

  FrameVisual settle(SubjectState? s, {bool ready = false}) {
    var v = const FrameVisual();
    for (var i = 0; i < 120; i++) {
      v = v.step(s, ready, 1 / 60);
    }
    return v;
  }

  test('자석: 멀면 사람을 따라가고 90점이면 목표에 붙는다', () {
    expect(settle(state(40)).live![BodyAnchor.head]!.dx, closeTo(200, 0.5));
    expect(settle(state(90)).live![BodyAnchor.head]!.dx, closeTo(180, 0.5));
    final mid = settle(state(75)).live![BodyAnchor.head]!.dx;
    expect(mid, inExclusiveRange(180, 200));
  });

  test('들어온 기준점만 반응', () {
    final v = settle(state(60, hits: {BodyAnchor.feet}));
    expect(v.hits[BodyAnchor.feet], closeTo(1, 0.01));
    expect(v.hits[BodyAnchor.head], 0);
  });

  test('완성되면 전환 값이 1로, 사람이 없으면 프레임이 사라짐', () {
    expect(settle(state(95), ready: true).ready, closeTo(1, 0.01));
    var v = settle(state(95));
    for (var i = 0; i < 120; i++) {
      v = v.step(null, false, 1 / 60);
    }
    expect(v.presence, closeTo(0, 0.01));
  });

  testWidgets('모든 안내 상태에서 오류 없이 그려진다', (tester) async {
    for (final action in CoachAction.values) {
      for (final ready in [false, true]) {
        await tester.pumpWidget(
          DynamicFrame(
            ready: ready,
            state: SubjectState(
              target: target,
              live: live,
              fit: SubjectFit(action: action, score: 70, scale: 1.2),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
  });
}
