import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'low_pass_filter.dart';

/// 세로 모드 기준 휴대폰 자세 (도 단위).
///
/// - [pitchDeg]: 카메라가 수평보다 아래를 보면 +, 위를 보면 − (`2.1-모바일-앱-설계.md` 5장과 동일)
/// - [rollDeg]: 화면 기준 반시계로 돌아가면 +
@immutable
class Attitude {
  const Attitude(this.pitchDeg, this.rollDeg, {this.yawDeg = 0});

  /// 중력 가속도(Android 규약: 정지 시 위쪽 축이 +g)로 계산.
  /// 세로로 세우면 (0, g, 0), 화면이 하늘을 보게 눕히면 (0, 0, g).
  factory Attitude.fromGravity(double x, double y, double z) {
    const toDeg = 180 / math.pi;
    return Attitude(math.atan2(z, y) * toDeg, math.atan2(x, y) * toDeg);
  }

  final double pitchDeg;
  final double rollDeg;

  /// 최근에 왼쪽으로 돌린 각도(+). 좌우는 목표 방위가 없으므로 가만히 있으면 0으로 돌아온다.
  final double yawDeg;

  /// 카메라가 위를 보는 각도 (로우앵글 +). 권장 각도([AngleSpec])와 같은 부호.
  double get elevationDeg => -pitchDeg;

  /// 전면 카메라 기준 자세: 카메라가 반대쪽을 보므로 상하가 뒤집히고,
  /// 프리뷰가 좌우반전이라 좌우 회전도 뒤집힌다. 화면에 보이는 수평(roll)은 같다.
  Attitude get forFrontCamera => Attitude(-pitchDeg, rollDeg, yawDeg: -yawDeg);

  /// 폰이 눕혀져(±60° 초과) 수평(roll) 값을 믿을 수 없는 상태인지.
  bool get isUpright => pitchDeg.abs() <= 60;

  @override
  String toString() =>
      'Attitude(pitch ${pitchDeg.toStringAsFixed(1)}, roll ${rollDeg.toStringAsFixed(1)})';
}

/// 가속도계(느리지만 안 밀림)와 자이로(빠르지만 밀림)를 합친 자세 추정 + 손떨림 로우패스.
///
/// 1. 중력 추정: 자이로로 빠르게 돌리고, 가속도계 쪽으로 [gravityTau]만큼 천천히 수렴
/// 2. 출력 각도: [smoothTau] 로우패스로 손떨림(약 8~12Hz) 제거
///
/// 자이로가 없는 기기에서는 가속도계만으로 동작한다.
class AttitudeFilter {
  AttitudeFilter({
    this.gravityTau = const Duration(milliseconds: 370),
    this.yawTau = const Duration(milliseconds: 800),
    Duration smoothTau = const Duration(milliseconds: 90),
  }) : _pitch = AngleLowPassFilter(smoothTau),
       _roll = AngleLowPassFilter(smoothTau);

  final AngleLowPassFilter _pitch;
  final AngleLowPassFilter _roll;

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
    final raw = Attitude.fromGravity(_x!, _y!, _z!);
    return Attitude(
      _pitch.add(raw.pitchDeg, dt),
      _roll.add(raw.rollDeg, dt),
      yawDeg: _yawRad * 180 / math.pi,
    );
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
