import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 앱이 쓰는 줌 범위 (기기 지원 범위 ∩ 0.5~3배).
@immutable
class ZoomRange {
  const ZoomRange(this.min, this.max);

  /// 기기 지원 범위에서 앱 범위를 계산. 기기가 0.5배 미만/3배 초과를 지원해도 잘라낸다.
  factory ZoomRange.fromDevice(double deviceMin, double deviceMax) {
    final min = math.max(deviceMin, appMin);
    final max = math.max(min, math.min(deviceMax, appMax));
    return ZoomRange(min, max);
  }

  static const appMin = 0.5;
  static const appMax = 3.0;

  /// 빠른 선택 버튼 배율
  static const stops = [0.5, 1.0, 2.0, 3.0];

  static const none = ZoomRange(1, 1);

  final double min;
  final double max;

  static const _epsilon = 0.01;

  double clamp(double level) => level.clamp(min, max);

  /// 이 범위에서 누를 수 있는 버튼 배율
  List<double> get availableStops => [
    for (final s in stops)
      if (s >= min - _epsilon && s <= max + _epsilon) s,
  ];

  /// 현재 배율이 속한 버튼 (현재 배율 이하인 가장 큰 버튼)
  double? activeStop(double level) {
    double? active;
    for (final s in availableStops) {
      if (s <= level + _epsilon) active = s;
    }
    return active ?? availableStops.firstOrNull;
  }

  /// 버튼 라벨. 활성 버튼은 실제 배율(예: 1.4x)을 보여준다.
  static String label(double stop, {double? current}) {
    final value = current ?? stop;
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return current == null ? text : '${text}x';
  }

  @override
  bool operator ==(Object other) =>
      other is ZoomRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}
