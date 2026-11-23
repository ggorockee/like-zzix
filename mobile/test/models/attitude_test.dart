import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/angle_spec.dart';
import 'package:likezzix/models/angle_state.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/models/low_pass_filter.dart';

const g = 9.81;

/// 세로로 든 폰을 카메라가 [upDeg]만큼 위를 보도록 기울였을 때의 중력값.
/// (위를 보려면 화면이 아래로 향하므로 z가 음수)
Attitude tiltedUp(double upDeg, {double rollDeg = 0}) {
  final p = upDeg * math.pi / 180;
  final r = rollDeg * math.pi / 180;
  final y = g * math.cos(p);
  return Attitude.fromGravity(y * math.tan(r), y, -g * math.sin(p));
}

void main() {
  group('Attitude.fromGravity', () {
    test('세로로 똑바로 세우면 0°', () {
      final a = Attitude.fromGravity(0, g, 0);
      expect(a.pitchDeg, closeTo(0, 1e-9));
      expect(a.rollDeg, closeTo(0, 1e-9));
    });

    test('카메라가 위를 보면 pitch 음수 (문서 규약)', () {
      expect(tiltedUp(12).pitchDeg, closeTo(-12, 1e-6));
    });

    test('화면이 하늘을 보게 눕히면 카메라는 바닥을 봄 → +90°', () {
      expect(Attitude.fromGravity(0, 0, g).pitchDeg, closeTo(90, 1e-9));
    });

    test('roll', () {
      expect(tiltedUp(0, rollDeg: 5).rollDeg, closeTo(5, 1e-6));
    });
  });

  group('AttitudeFilter', () {
    final start = DateTime(2026, 11, 23);
    DateTime at(int i) => start.add(Duration(milliseconds: 20 * i));
    const deg = math.pi / 180;

    test('튀는 값 하나는 크게 반영되지 않음', () {
      final filter = AttitudeFilter();
      for (var i = 0; i < 50; i++) {
        filter.addAccelerometer(0, g, 0, at(i));
      }
      final a = filter.addAccelerometer(0, 0, g, at(50)); // 순간 충격
      expect(a.pitchDeg, lessThan(15));
    });

    test('자이로가 없어도 1.5초 안에 실제 각도로 수렴', () {
      final filter = AttitudeFilter()..addAccelerometer(0, g, 0, at(0));
      late Attitude a;
      for (var i = 1; i <= 75; i++) {
        a = filter.addAccelerometer(
          0,
          g * math.cos(20 * deg),
          -g * math.sin(20 * deg),
          at(i),
        );
      }
      expect(a.pitchDeg, closeTo(-20, 1));
    });

    test('빠르게 기울이면 자이로 덕분에 지연 없이 따라감', () {
      // 0.2초 동안 카메라를 20° 위로 (윗변이 몸 쪽으로 = x축 +회전)
      final filter = AttitudeFilter()
        ..addAccelerometer(0, g, 0, at(0))
        ..addGyroscope(0, 0, 0, at(0));
      late Attitude a;
      for (var i = 1; i <= 10; i++) {
        filter.addGyroscope(100 * deg, 0, 0, at(i));
        final p = 2.0 * i * deg;
        a = filter.addAccelerometer(
          0,
          g * math.cos(p),
          -g * math.sin(p),
          at(i),
        );
      }
      // 손떨림 로우패스(0.09초) 지연만 남는다
      expect(a.pitchDeg, inInclusiveRange(-20, -11));
    });

    test('반시계로 돌리면 roll +', () {
      final filter = AttitudeFilter()
        ..addAccelerometer(0, g, 0, at(0))
        ..addGyroscope(0, 0, 0, at(0));
      late Attitude a;
      for (var i = 1; i <= 5; i++) {
        filter.addGyroscope(0, 0, 100 * deg, at(i));
        final r = 2.0 * i * deg;
        a = filter.addAccelerometer(g * math.sin(r), g * math.cos(r), 0, at(i));
      }
      expect(a.rollDeg, inInclusiveRange(3, 10));
    });

    test('왼쪽으로 돌리면 yaw +, 멈추면 0으로 돌아옴', () {
      final filter = AttitudeFilter()
        ..addAccelerometer(0, g, 0, at(0))
        ..addGyroscope(0, 0, 0, at(0));
      for (var i = 1; i <= 10; i++) {
        filter.addGyroscope(0, 100 * deg, 0, at(i));
      }
      final turned = filter.addAccelerometer(0, g, 0, at(10));
      expect(turned.yawDeg, inInclusiveRange(16, 20));
      for (var i = 11; i <= 210; i++) {
        filter.addGyroscope(0, 0, 0, at(i));
      }
      expect(filter.addAccelerometer(0, g, 0, at(210)).yawDeg, lessThan(0.5));
    });

    test('오래 멈췄다 재개돼도 튀지 않음', () {
      final filter = AttitudeFilter()
        ..addAccelerometer(0, g, 0, at(0))
        ..addGyroscope(0, 0, 0, at(0))
        ..addGyroscope(0, 1, 0, at(500));
      expect(
        filter.addAccelerometer(0, g, 0, at(500)).yawDeg,
        lessThanOrEqualTo(6),
      );
    });
  });

  test('전면 카메라는 상하·좌우 회전이 뒤집히고 수평은 그대로', () {
    final a = const Attitude(10, 5, yawDeg: 3).forFrontCamera;
    expect((a.pitchDeg, a.rollDeg, a.yawDeg), (-10, 5, -3));
  });

  group('AngleStateMachine (사진 프리셋: -12° ± 3°)', () {
    AngleStateMachine machine([double pitchDeg = -12]) =>
        AngleStateMachine(AngleSpec.target(pitchDeg: pitchDeg));

    test('범위 안이면 초록', () {
      final guide = machine().add(tiltedUp(11));
      expect(guide.state, AngleState.good);
      expect(guide.tilt, TiltHint.none);
    });

    test('덜 기울였으면 범위까지 남은 각도만큼 위로 향하라고 안내', () {
      final guide = machine().add(tiltedUp(0));
      expect(guide.state, AngleState.off);
      expect(guide.tilt, TiltHint.aimUp);
      expect(guide.pitchError, closeTo(9, 1e-6));
    });

    test('너무 위를 보면 아래로 안내', () {
      expect(machine().add(tiltedUp(25)).tilt, TiltHint.aimDown);
    });

    test('수평이 틀어지면 회전 안내', () {
      final guide = machine(0).add(tiltedUp(0, rollDeg: 6));
      expect(guide.tilt, TiltHint.none);
      expect(guide.level, LevelHint.rotateClockwise);
    });

    test('폰을 눕히면 대기 + 세우라는 안내', () {
      final guide = machine(0).add(Attitude.fromGravity(0.3, 0.2, g));
      expect(guide.upright, isFalse);
      expect(guide.state, AngleState.waiting);
      expect(guide.rollDelta, 0);
    });
  });

  group('히스테리시스 (전신: 위로 5~10°, 수평 ±3°)', () {
    const spec = AngleSpec(elevationMin: 5, elevationMax: 10);
    AngleState at(AngleStateMachine m, double up, [double roll = 0]) =>
        m.add(tiltedUp(up, rollDeg: roll)).state;

    test('경계에서 떨려도 초록이 한 번만 켜진다 (채터링 방지)', () {
      final m = AngleStateMachine(spec);
      var entries = 0;
      var before = AngleState.off;
      // 경계(5°)를 ±1.8° 폭으로 오가는 손떨림
      for (var i = 0; i < 200; i++) {
        final now = at(m, 5 + 1.8 * math.sin(i * 0.7));
        if (now == AngleState.good && before != AngleState.good) entries++;
        before = now;
      }
      expect(entries, 1);
    });

    test('이탈은 버퍼 2°를 넘어야, 재진입은 범위 안이어야', () {
      final m = AngleStateMachine(spec);
      expect(at(m, 4.5), AngleState.off);
      expect(at(m, 6), AngleState.good);
      expect(at(m, 3.2), AngleState.good); // 버퍼 안
      expect(at(m, 11.9), AngleState.good);
      expect(at(m, 2.8), AngleState.off);
      expect(at(m, 4.5), AngleState.off); // 버퍼 구간에서는 재진입 안 됨
      expect(at(m, 5.1), AngleState.good);
    });

    test('수평도 같은 방식 (진입 3°, 이탈 4.5°)', () {
      final m = AngleStateMachine(spec);
      expect(at(m, 7, 3.5), AngleState.off);
      expect(at(m, 7, 2.5), AngleState.good);
      expect(at(m, 7, 4.2), AngleState.good);
      expect(at(m, 7, 4.8), AngleState.off);
    });
  });

  test('로우패스: 10Hz ±1° 손떨림을 1/4 아래로 줄이고 실제 이동은 따라간다', () {
    final lpf = AngleLowPassFilter(const Duration(milliseconds: 90));
    var peak = 0.0;
    for (var i = 0; i < 200; i++) {
      final v = lpf.add(math.sin(2 * math.pi * 10 * i * 0.02), 0.02);
      if (i > 50) peak = math.max(peak, v.abs());
    }
    expect(peak, lessThan(0.25));

    final step = AngleLowPassFilter(const Duration(milliseconds: 90))
      ..add(0, 0);
    late double v;
    for (var i = 0; i < 15; i++) {
      v = step.add(10, 0.02);
    }
    expect(v, greaterThan(9.5)); // 0.3초 안에 95%
  });

  test('로우패스: ±180° 경계에서 짧은 쪽으로', () {
    final lpf = AngleLowPassFilter(const Duration(milliseconds: 90))
      ..add(179, 0);
    expect(lpf.add(-179, 0.02), greaterThan(179));
  });
}
