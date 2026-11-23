import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/guide_motion.dart';

void main() {
  const screen = Size(400, 800);
  const center = Offset(200, 400);
  const focal = 600.0;

  GuideMotion motion({double pitch = 0, double roll = 0, double yaw = 0}) =>
      GuideMotion(pitchDeg: pitch, rollDeg: roll, yawDeg: yaw, locked: false);

  Offset move(GuideMotion m, Offset p) =>
      MatrixUtils.transformPoint(m.matrix(screen, focal), p);

  group('화면 이동 방향', () {
    test('벗어나지 않으면 그대로', () {
      const p = Offset(120, 300);
      expect((move(motion(), p) - p).distance, lessThan(1e-6));
    });

    test('카메라가 아래를 보면 가이드는 위로, 위를 보면 아래로 (f·tanθ)', () {
      final up = move(motion(pitch: 10), center);
      expect(up.dx, closeTo(200, 1e-6));
      expect(up.dy, closeTo(400 - 600 * 0.17633, 0.01));
      expect(move(motion(pitch: -10), center).dy, greaterThan(400));
    });

    test('왼쪽으로 돌리면 가이드는 오른쪽으로', () {
      final right = move(motion(yaw: 10), center);
      expect(right.dx, closeTo(200 + 600 * 0.17633, 0.01));
      expect(right.dy, closeTo(400, 1e-6));
    });

    test('폰이 반시계로 돌면 가이드는 시계 방향 (화면 중심 기준)', () {
      final p = move(motion(roll: 90), const Offset(300, 400));
      expect(p.dx, closeTo(200, 1e-6));
      expect(p.dy, closeTo(500, 1e-6));
    });

    test('원근: 위로 밀린 가이드는 멀어진 윗변이 아랫변과 다른 폭', () {
      final m = motion(pitch: 20);
      final top =
          move(m, const Offset(300, 300)).dx -
          move(m, const Offset(100, 300)).dx;
      final bottom =
          move(m, const Offset(300, 500)).dx -
          move(m, const Offset(100, 500)).dx;
      expect((top - bottom).abs(), greaterThan(10));
    });

    test('표시 한계에서도 화면 모서리가 뒤집히지 않음', () {
      final m = motion(
        pitch: GuideMotion.maxTiltDeg,
        roll: GuideMotion.maxRollDeg,
        yaw: GuideMotion.maxTiltDeg,
      ).matrix(screen, focal);
      for (final p in [
        Offset.zero,
        const Offset(400, 0),
        const Offset(0, 800),
        const Offset(400, 800),
      ]) {
        // 동차 좌표 w가 양수여야 카메라 앞쪽
        final w = m.entry(3, 0) * p.dx + m.entry(3, 1) * p.dy + m.entry(3, 3);
        expect(w, greaterThan(0));
      }
    });
  });

  group('GuideMotionFilter', () {
    GuideMotion run(
      GuideMotionFilter f, {
      bool matched = false,
      double pitch = 0,
      double yaw = 0,
      int times = 60,
    }) {
      late GuideMotion m;
      for (var i = 0; i < times; i++) {
        m = f.add(
          angleMatched: matched,
          pitchError: pitch,
          rollError: 0,
          yawDeg: yaw,
        );
      }
      return m;
    }

    test('벗어난 각도를 따라가고 한계에서 멈춤', () {
      expect(run(GuideMotionFilter(), pitch: 8).pitchDeg, 8);
      expect(
        run(GuideMotionFilter(), pitch: 80).pitchDeg,
        GuideMotion.maxTiltDeg,
      );
    });

    test('각도가 맞으면 튀지 않고 부드럽게 프레임에 붙음', () {
      final f = GuideMotionFilter();
      run(f, pitch: 3.5);
      final first = run(f, matched: true, pitch: 2.9, times: 1);
      expect(first.locked, isTrue);
      expect(first.pitchDeg, inExclusiveRange(0, 3.5));
      expect(run(f, matched: true, pitch: 2.9).isStill, isTrue);
    });

    test('좌우로 돌리는 중이면 고정되지 않고, 경계에서 깜빡이지 않음', () {
      final f = GuideMotionFilter();
      expect(run(f, matched: true, yaw: 6).locked, isFalse);
      expect(run(f, matched: true, yaw: 3).locked, isFalse);
      expect(run(f, matched: true, yaw: 1).locked, isTrue);
      expect(run(f, matched: true, yaw: 3).locked, isTrue);
      expect(run(f, matched: true, yaw: 5).locked, isFalse);
    });
  });
}
