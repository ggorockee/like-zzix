import 'dart:math' as math;

/// 각도용 1차 로우패스 필터. 샘플 간격이 들쭉날쭉해도 시간 상수([tau])만큼 일정하게 부드럽다.
/// ±180° 경계에서는 짧은 쪽으로 따라간다.
class AngleLowPassFilter {
  AngleLowPassFilter(this.tau);

  final Duration tau;
  double? _value;

  /// [dtSeconds]는 직전 샘플 이후 지난 시간.
  double add(double degrees, double dtSeconds) {
    final last = _value;
    if (last == null) return _value = degrees;
    final gain = 1 - math.exp(-dtSeconds * 1e6 / tau.inMicroseconds);
    final diff = (degrees - last + 540) % 360 - 180;
    return _value = last + gain * diff;
  }
}
