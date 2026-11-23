import 'package:flutter/foundation.dart';

/// 권장 촬영 각도 범위.
///
/// 부호는 촬영자 기준: **카메라가 위를 보면(로우앵글) +**, 아래를 보면 −.
/// 센서 자세([Attitude.pitchDeg])와 서버 `pitch_deg`는 반대 부호라 여기서만 변환한다.
@immutable
class AngleSpec {
  const AngleSpec({
    required this.elevationMin,
    required this.elevationMax,
    this.rollTarget = 0,
    this.rollTolerance = 3,
  }) : assert(elevationMin <= elevationMax);

  /// 사진 프리셋: 기준 각도 하나(서버 부호, 위 = −)에서 ±3°, 수평 ±2°
  const AngleSpec.target({required double pitchDeg, double rollDeg = 0})
    : elevationMin = -pitchDeg - 3,
      elevationMax = -pitchDeg + 3,
      rollTarget = rollDeg,
      rollTolerance = 2;

  factory AngleSpec.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    final min = read('elevation_min', -3);
    final max = read('elevation_max', 3);
    if (min > max) throw const FormatException('elevation_min > elevation_max');
    return AngleSpec(
      elevationMin: min,
      elevationMax: max,
      rollTarget: read('roll_target', 0),
      rollTolerance: read('roll_tolerance', 3),
    );
  }

  /// 프리셋을 고르기 전: 수평만 안내
  static const level = AngleSpec.target(pitchDeg: 0);

  final double elevationMin;
  final double elevationMax;
  final double rollTarget;
  final double rollTolerance;

  double get elevationMid => (elevationMin + elevationMax) / 2;

  /// 범위를 벗어난 정도(도). 카메라를 더 위로 향해야 하면 +, 아래면 −, 범위 안이면 0.
  double elevationError(double elevation) {
    if (elevation < elevationMin) return elevationMin - elevation;
    if (elevation > elevationMax) return elevationMax - elevation;
    return 0;
  }

  /// 수평 범위를 벗어난 정도(도). 폰을 시계 방향으로 돌려야 하면 +, 범위 안이면 0.
  double rollError(double roll) {
    final delta = roll - rollTarget;
    if (delta > rollTolerance) return delta - rollTolerance;
    if (delta < -rollTolerance) return delta + rollTolerance;
    return 0;
  }
}
