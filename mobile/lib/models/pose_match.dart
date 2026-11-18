import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'preset.dart';

/// 촬영자에게 줄 안내 (우선순위 순).
enum PoseHint {
  /// 사람이 인식되지 않음
  noPerson,

  /// 레퍼런스에 보이는 신체 부위가 충분히 보이지 않음
  showMoreBody,

  /// 사람이 작게 보임 → 다가가기
  stepCloser,

  /// 사람이 크게 보임 → 물러나기
  stepBack,

  /// 사람이 목표보다 오른쪽 → 카메라를 오른쪽으로
  panRight,
  panLeft,

  /// 사람이 목표보다 아래 → 폰 높이를 낮추기
  lowerPhone,
  raisePhone,

  /// 위치·크기는 맞지만 자세가 다름
  adjustPose,

  /// 일치
  matched,
}

@immutable
class PoseMatchResult {
  const PoseMatchResult({
    required this.hint,
    required this.matched,
    this.error,
    this.jointOk = const {},
  });

  /// 평균 관절 거리 ÷ 기준 길이. 비교할 수 없으면 null.
  final double? error;
  final PoseHint hint;
  final bool matched;

  /// 관절 인덱스 → 목표 위치 근처인지
  final Map<int, bool> jointOk;

  /// 0~100 일치도 (표시용)
  int get score =>
      error == null ? 0 : ((1 - error! / 0.5).clamp(0.0, 1.0) * 100).round();
}

/// 레퍼런스 포즈와 실시간 포즈의 구도 일치 판정 (`01_MOBILE.md` 6.4).
///
/// 위치·크기를 그대로 비교하므로 "포즈"뿐 아니라 "구도"(화면 내 위치·크기)까지
/// 맞아야 일치한다. 경계에서 깜빡이지 않도록 진입/해제 기준을 다르게 둔다.
class PoseMatcher {
  PoseMatcher({this.enterError = 0.10, this.exitError = 0.13});

  final double enterError;
  final double exitError;

  /// 비교 관절: 코, 어깨, 팔꿈치, 손목, 엉덩이, 무릎, 발목
  static const joints = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];

  /// 관절 하나가 "맞다"고 보는 거리 (기준 길이 대비)
  static const jointTolerance = 0.18;

  bool _matched = false;

  void reset() => _matched = false;

  /// [reference]·[live]는 프레임 정규화 좌표. [aspectRatio]는 프레임 가로/세로.
  PoseMatchResult evaluate(
    List<PoseLandmark> reference,
    List<PoseLandmark>? live, {
    required double aspectRatio,
  }) {
    if (live == null || live.length < PoseIndex.count) {
      _matched = false;
      return const PoseMatchResult(hint: PoseHint.noPerson, matched: false);
    }

    final expected = [
      for (final j in joints)
        if (reference[j].isVisible) j,
    ];
    final common = [
      for (final j in expected)
        if (live[j].isVisible) j,
    ];
    final required = math.max(4, (expected.length * 0.7).ceil());
    if (common.length < math.min(required, expected.length)) {
      _matched = false;
      return const PoseMatchResult(hint: PoseHint.showMoreBody, matched: false);
    }

    // 가로세로 길이를 같은 단위(프레임 높이)로 맞춤
    Offset p(PoseLandmark l) => Offset(l.x * aspectRatio, l.y);
    final base = _baseLength(reference, p);

    final jointOk = <int, bool>{};
    var sum = 0.0;
    for (final j in common) {
      final d = (p(live[j]) - p(reference[j])).distance / base;
      sum += d;
      jointOk[j] = d <= jointTolerance;
    }
    final error = sum / common.length;
    _matched = error < (_matched ? exitError : enterError);

    return PoseMatchResult(
      error: error,
      matched: _matched,
      jointOk: jointOk,
      hint: _matched
          ? PoseHint.matched
          : _hint(
              [for (final j in common) p(reference[j])],
              [for (final j in common) p(live[j])],
              base,
            ),
    );
  }

  /// 기준 길이: 몸통(어깨 중점~엉덩이 중점), 어깨너비, 머리~어깨 중 가장 긴 것.
  static double _baseLength(
    List<PoseLandmark> ref,
    Offset Function(PoseLandmark) p,
  ) {
    bool v(int i) => ref[i].isVisible;
    final candidates = <double>[];
    if (v(11) && v(12)) {
      final shoulderMid = Offset.lerp(p(ref[11]), p(ref[12]), 0.5)!;
      candidates.add((p(ref[11]) - p(ref[12])).distance);
      if (v(23) && v(24)) {
        final hipMid = Offset.lerp(p(ref[23]), p(ref[24]), 0.5)!;
        candidates.add((shoulderMid - hipMid).distance);
      }
      if (v(0)) candidates.add((p(ref[0]) - shoulderMid).distance * 1.5);
    }
    final base = candidates.isEmpty ? 0.25 : candidates.reduce(math.max);
    return math.max(base, 0.05);
  }

  /// 위치·크기 차이로 가장 먼저 고칠 것을 고른다.
  static PoseHint _hint(List<Offset> ref, List<Offset> live, double base) {
    Offset centroid(List<Offset> pts) =>
        pts.reduce((a, b) => a + b) / pts.length.toDouble();
    double spread(List<Offset> pts, Offset c) =>
        pts.map((q) => (q - c).distance).reduce((a, b) => a + b) / pts.length;

    final rc = centroid(ref);
    final lc = centroid(live);
    final rs = spread(ref, rc);
    if (rs > 0) {
      final scale = spread(live, lc) / rs;
      if (scale < 0.85) return PoseHint.stepCloser;
      if (scale > 1.18) return PoseHint.stepBack;
    }
    final dx = (lc.dx - rc.dx) / base;
    final dy = (lc.dy - rc.dy) / base;
    if (dx.abs() >= dy.abs() && dx.abs() > 0.2) {
      return dx > 0 ? PoseHint.panRight : PoseHint.panLeft;
    }
    if (dy.abs() > 0.2) {
      return dy > 0 ? PoseHint.lowerPhone : PoseHint.raisePhone;
    }
    return PoseHint.adjustPose;
  }
}
