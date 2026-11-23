import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 세로 모드 기준 휴대폰 자세 (도 단위).
///
/// - [pitchDeg]: 카메라가 수평보다 아래를 보면 +, 위를 보면 − (`01_MOBILE.md` 5장과 동일)
/// - [rollDeg]: 화면 기준 반시계로 돌아가면 +
@immutable
class Attitude {
  const Attitude(this.pitchDeg, this.rollDeg, {this.yawDeg = 0});

  /// 중력 가속도(Android 규약: 정지 시 위쪽 축이 +g)로 계산.
  /// 세로로 세우면 (0, g, 0), 화면이 하늘을 보게 눕히면 (0, 0, g).
  factory Attitude.fromGravity(
    double x,
    double y,
    double z, {
    double yawDeg = 0,
  }) {
    const toDeg = 180 / math.pi;
    return Attitude(
      math.atan2(z, y) * toDeg,
      math.atan2(x, y) * toDeg,
      yawDeg: yawDeg,
    );
  }

  final double pitchDeg;
  final double rollDeg;

  /// 최근에 왼쪽으로 돌린 각도(+). 좌우는 목표 방위가 없으므로 가만히 있으면 0으로 돌아온다.
  final double yawDeg;

  /// 전면 카메라 기준 자세: 카메라가 반대쪽을 보므로 상하가 뒤집히고,
  /// 프리뷰가 좌우반전이라 좌우 회전도 뒤집힌다. 화면에 보이는 수평(roll)은 같다.
  Attitude get forFrontCamera => Attitude(-pitchDeg, rollDeg, yawDeg: -yawDeg);

  /// 폰이 눕혀져(±60° 초과) 수평(roll) 값을 믿을 수 없는 상태인지.
  bool get isUpright => pitchDeg.abs() <= 60;

  @override
  String toString() =>
      'Attitude(pitch ${pitchDeg.toStringAsFixed(1)}, roll ${rollDeg.toStringAsFixed(1)})';
}

/// 가속도계(느리지만 안 밀림)와 자이로(빠르지만 밀림)를 합친 자세 추정.
/// 자이로가 없는 기기에서는 가속도계 저역 통과 필터로만 동작한다.
class AttitudeFilter {
  AttitudeFilter({
    this.gravityTau = const Duration(milliseconds: 370),
    this.yawTau = const Duration(milliseconds: 800),
  });

  /// 가속도계 값으로 수렴하는 시간 상수
  final Duration gravityTau;

  /// 좌우 회전이 0으로 돌아오는 시간 상수
  final Duration yawTau;

  double? _x, _y, _z;
  double _yawRad = 0;
  DateTime? _accelAt, _gyroAt;

  /// 앱이 잠깐 멈췄다 재개돼도 값이 튀지 않도록 한 번에 반영하는 최대 시간(초)
  static const _maxStep = 0.1;

  static double _elapsed(DateTime? from, DateTime to) {
    if (from == null) return 0;
    return (to.difference(from).inMicroseconds / 1e6).clamp(0, _maxStep);
  }

  static double _seconds(Duration d) => d.inMicroseconds / 1e6;

  Attitude addAccelerometer(double x, double y, double z, DateTime at) {
    final dt = _elapsed(_accelAt, at);
    _accelAt = at;
    final k = 1 - math.exp(-dt / _seconds(gravityTau));
    _x = _x == null ? x : _x! + k * (x - _x!);
    _y = _y == null ? y : _y! + k * (y - _y!);
    _z = _z == null ? z : _z! + k * (z - _z!);
    return Attitude.fromGravity(_x!, _y!, _z!, yawDeg: _yawRad * 180 / math.pi);
  }

  /// 각속도(rad/s, 기기 축 기준 오른손 법칙).
  void addGyroscope(double wx, double wy, double wz, DateTime at) {
    final dt = _elapsed(_gyroAt, at);
    _gyroAt = at;
    final gx = _x, gy = _y, gz = _z;
    if (gx == null || gy == null || gz == null || dt == 0) return;

    // 세상에 고정된 '위' 방향은 기기가 도는 만큼 기기 축에서 반대로 돈다: dg = −ω × g
    _x = gx - (wy * gz - wz * gy) * dt;
    _y = gy - (wz * gx - wx * gz) * dt;
    _z = gz - (wx * gy - wy * gx) * dt;

    // 위 방향을 축으로 한 회전 = 좌우 회전 (왼쪽 +). 서서히 0으로 되돌린다.
    final norm = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (norm == 0) return;
    final rate = (wx * gx + wy * gy + wz * gz) / norm;
    _yawRad = (_yawRad + rate * dt) * math.exp(-dt / _seconds(yawTau));
  }
}

enum TiltHint { none, aimUp, aimDown }

enum LevelHint { none, rotateClockwise, rotateCounterClockwise }

/// 목표 각도와의 차이 및 안내.
@immutable
class AngleGuide {
  const AngleGuide({
    required this.pitchDelta,
    required this.rollDelta,
    required this.matched,
    required this.tilt,
    required this.level,
    this.upright = true,
    this.yawDeg = 0,
  });

  /// 현재 − 목표 (도)
  final double pitchDelta;
  final double rollDelta;
  final bool matched;
  final TiltHint tilt;
  final LevelHint level;

  /// false면 폰을 세워 달라는 안내가 우선 (이때 roll은 0으로 취급).
  final bool upright;

  /// 최근 좌우 회전 ([Attitude.yawDeg])
  final double yawDeg;
}

/// 목표 각도 일치 판정. 경계에서 깜빡이지 않도록 히스테리시스 적용.
class AngleMatcher {
  AngleMatcher({
    this.pitchTolerance = 3,
    this.rollTolerance = 2,
    this.releaseFactor = 1.5,
  });

  final double pitchTolerance;
  final double rollTolerance;

  /// 일치 상태에서 해제되려면 허용 오차의 몇 배를 벗어나야 하는지.
  final double releaseFactor;

  bool _matched = false;

  AngleGuide evaluate(
    Attitude attitude, {
    required double targetPitchDeg,
    double targetRollDeg = 0,
  }) {
    final pitchDelta = attitude.pitchDeg - targetPitchDeg;
    if (!attitude.isUpright) {
      _matched = false;
      return AngleGuide(
        pitchDelta: pitchDelta,
        rollDelta: 0,
        matched: false,
        tilt: pitchDelta > 0 ? TiltHint.aimUp : TiltHint.aimDown,
        level: LevelHint.none,
        upright: false,
        yawDeg: attitude.yawDeg,
      );
    }
    final rollDelta = attitude.rollDeg - targetRollDeg;
    final factor = _matched ? releaseFactor : 1.0;
    final pitchOk = pitchDelta.abs() <= pitchTolerance * factor;
    final rollOk = rollDelta.abs() <= rollTolerance * factor;
    _matched = pitchOk && rollOk;

    return AngleGuide(
      pitchDelta: pitchDelta,
      rollDelta: rollDelta,
      matched: _matched,
      tilt: pitchOk
          ? TiltHint.none
          : pitchDelta > 0
          ? TiltHint.aimUp
          : TiltHint.aimDown,
      level: rollOk
          ? LevelHint.none
          : rollDelta > 0
          ? LevelHint.rotateClockwise
          : LevelHint.rotateCounterClockwise,
      yawDeg: attitude.yawDeg,
    );
  }
}
