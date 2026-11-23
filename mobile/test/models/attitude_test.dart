import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/widgets/angle_indicator.dart';

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
      expect(a.pitchDeg, closeTo(-20, 1));
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
      expect(a.rollDeg, closeTo(10, 1));
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

  group('AngleMatcher', () {
    test('목표 범위 안이면 일치', () {
      final guide = AngleMatcher().evaluate(tiltedUp(11), targetPitchDeg: -12);
      expect(guide.matched, isTrue);
      expect(guide.tilt, TiltHint.none);
    });

    test('덜 기울였으면 위로 향하라고 안내', () {
      final guide = AngleMatcher().evaluate(tiltedUp(0), targetPitchDeg: -12);
      expect(guide.matched, isFalse);
      expect(guide.tilt, TiltHint.aimUp);
      expect(
        AngleStatus.message(guide, hasPreset: true).$2,
        '카메라를 위로 12° 더 향하게',
      );
    });

    test('너무 위를 보면 아래로 안내', () {
      final guide = AngleMatcher().evaluate(tiltedUp(25), targetPitchDeg: -12);
      expect(guide.tilt, TiltHint.aimDown);
    });

    test('수평이 틀어지면 회전 안내', () {
      final guide = AngleMatcher().evaluate(
        tiltedUp(0, rollDeg: 6),
        targetPitchDeg: 0,
      );
      expect(guide.tilt, TiltHint.none);
      expect(guide.level, LevelHint.rotateClockwise);
    });

    test('폰을 눕히면 수평 판단 없이 세우라는 안내', () {
      final guide = AngleMatcher().evaluate(
        Attitude.fromGravity(0.3, 0.2, g),
        targetPitchDeg: 0,
      );
      expect(guide.upright, isFalse);
      expect(guide.matched, isFalse);
      expect(guide.rollDelta, 0);
      expect(AngleStatus.message(guide, hasPreset: false).$2, '폰을 세워서 들어 주세요');
    });

    test('히스테리시스: 경계 근처에서 깜빡이지 않음', () {
      final matcher = AngleMatcher();
      expect(
        matcher.evaluate(tiltedUp(12), targetPitchDeg: -12).matched,
        isTrue,
      );
      // 진입 기준(3°)은 넘었지만 해제 기준(4.5°) 안
      expect(
        matcher.evaluate(tiltedUp(16), targetPitchDeg: -12).matched,
        isTrue,
      );
      expect(
        matcher.evaluate(tiltedUp(17), targetPitchDeg: -12).matched,
        isFalse,
      );
      // 다시 들어올 때는 진입 기준 적용
      expect(
        matcher.evaluate(tiltedUp(16), targetPitchDeg: -12).matched,
        isFalse,
      );
    });
  });
}
