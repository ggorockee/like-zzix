import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 세로 모드 기준 휴대폰 자세 (도 단위).
///
/// - [pitchDeg]: 카메라가 수평보다 아래를 보면 +, 위를 보면 − (`01_MOBILE.md` 5장과 동일)
/// - [rollDeg]: 화면 기준 반시계로 돌아가면 +
@immutable
class Attitude {
  const Attitude(this.pitchDeg, this.rollDeg);

  /// 중력 가속도(Android 규약: 정지 시 위쪽 축이 +g)로 계산.
  /// 세로로 세우면 (0, g, 0), 화면이 하늘을 보게 눕히면 (0, 0, g).
  factory Attitude.fromGravity(double x, double y, double z) {
    const toDeg = 180 / math.pi;
    return Attitude(math.atan2(z, y) * toDeg, math.atan2(x, y) * toDeg);
  }

  final double pitchDeg;
  final double rollDeg;

  /// 폰이 눕혀져(±60° 초과) 수평(roll) 값을 믿을 수 없는 상태인지.
  bool get isUpright => pitchDeg.abs() <= 60;

  @override
  String toString() =>
      'Attitude(pitch ${pitchDeg.toStringAsFixed(1)}, roll ${rollDeg.toStringAsFixed(1)})';
}

/// 가속도계 잡음을 줄이는 저역 통과 필터 (지수 이동 평균).
class GravityFilter {
  GravityFilter({this.alpha = 0.15});

  final double alpha;
  double? _x, _y, _z;

  Attitude add(double x, double y, double z) {
    _x = _x == null ? x : _x! + alpha * (x - _x!);
    _y = _y == null ? y : _y! + alpha * (y - _y!);
    _z = _z == null ? z : _z! + alpha * (z - _z!);
    return Attitude.fromGravity(_x!, _y!, _z!);
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
  });

  /// 현재 − 목표 (도)
  final double pitchDelta;
  final double rollDelta;
  final bool matched;
  final TiltHint tilt;
  final LevelHint level;

  /// false면 폰을 세워 달라는 안내가 우선 (이때 roll은 0으로 취급).
  final bool upright;
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
    );
  }
}
