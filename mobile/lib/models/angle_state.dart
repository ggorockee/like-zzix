import 'package:flutter/foundation.dart';

import 'angle_spec.dart';
import 'attitude.dart';

/// 각도 신호등.
enum AngleState {
  /// 센서 값이 없거나 폰이 눕혀져 있음 (흰색)
  waiting,

  /// 권장 범위를 벗어남 (노란색 + 방향 힌트)
  off,

  /// 권장 범위 (초록색)
  good,
}

enum TiltHint { none, aimUp, aimDown }

enum LevelHint { none, rotateClockwise, rotateCounterClockwise }

/// 권장 범위와의 차이 및 안내.
@immutable
class AngleGuide {
  const AngleGuide({
    required this.state,
    required this.pitchDelta,
    required this.rollDelta,
    this.pitchError = 0,
    this.rollError = 0,
    this.yawDeg = 0,
    this.upright = true,
  });

  final AngleState state;

  /// 권장 범위 중앙과의 차이 (카메라가 더 아래를 보면 +). 기울기 인디케이터용.
  final double pitchDelta;
  final double rollDelta;

  /// 권장 범위를 벗어난 정도. 범위 안이면 0.
  final double pitchError;
  final double rollError;

  /// 최근 좌우 회전 ([Attitude.yawDeg])
  final double yawDeg;

  /// false면 폰을 세워 달라는 안내가 우선 (이때 수평은 판단하지 않음).
  final bool upright;

  bool get matched => state == AngleState.good;

  /// 방향 힌트는 각도 이탈 상태에서만 (초록 상태의 버퍼 안 이탈은 알리지 않음).
  TiltHint get tilt => state != AngleState.off || pitchError == 0
      ? TiltHint.none
      : pitchError > 0
      ? TiltHint.aimUp
      : TiltHint.aimDown;

  LevelHint get level => state != AngleState.off || rollError == 0
      ? LevelHint.none
      : rollError > 0
      ? LevelHint.rotateClockwise
      : LevelHint.rotateCounterClockwise;
}

/// 히스테리시스 상태 판정.
///
/// - 진입(→ 초록): 권장 범위 안에 들어오면
/// - 이탈(초록 →): 권장 범위에서 버퍼([pitchBuffer]·[rollBuffer]) 넘게 벗어나야
///
/// 경계에서 손이 떨려도 초록불과 진동이 반복되지 않는다.
class AngleStateMachine {
  AngleStateMachine(this.spec, {this.pitchBuffer = 2, this.rollBuffer = 1.5});

  final AngleSpec spec;
  final double pitchBuffer;
  final double rollBuffer;

  bool _good = false;

  AngleGuide add(Attitude attitude) {
    final pitchError = spec.elevationError(attitude.elevationDeg);
    final pitchDelta = spec.elevationMid - attitude.elevationDeg;
    if (!attitude.isUpright) {
      _good = false;
      return AngleGuide(
        state: AngleState.waiting,
        pitchDelta: pitchDelta,
        rollDelta: 0,
        yawDeg: attitude.yawDeg,
        upright: false,
      );
    }
    final rollError = spec.rollError(attitude.rollDeg);
    _good =
        pitchError.abs() <= (_good ? pitchBuffer : 0) &&
        rollError.abs() <= (_good ? rollBuffer : 0);
    return AngleGuide(
      state: _good ? AngleState.good : AngleState.off,
      pitchDelta: pitchDelta,
      rollDelta: attitude.rollDeg - spec.rollTarget,
      pitchError: pitchError,
      rollError: rollError,
      yawDeg: attitude.yawDeg,
    );
  }
}
