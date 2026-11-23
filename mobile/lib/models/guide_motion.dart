import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/rendering.dart' show Matrix4, MatrixUtils;
import 'package:flutter/foundation.dart';

import 'preset.dart';

/// 목표 각도에서 벗어난 만큼 레퍼런스 가이드를 움직이는 양 (도 단위, 0이면 프레임에 고정).
///
/// 카메라를 제자리에서 돌리면 실제 장면은 화면에서 회전 호모그래피만큼 움직인다.
/// 가이드에 같은 변환을 적용하면 가이드가 공간에 붙어 있는 것처럼 보인다.
/// - 사람 ↔ 가이드 차이 = 서 있는 위치·거리·포즈가 틀림
/// - 가이드 ↔ 프레임 차이 = 폰 각도가 틀림
@immutable
class GuideMotion {
  const GuideMotion({
    required this.pitchDeg,
    required this.rollDeg,
    required this.yawDeg,
    required this.locked,
  });

  static const still = GuideMotion(
    pitchDeg: 0,
    rollDeg: 0,
    yawDeg: 0,
    locked: false,
  );

  /// 카메라가 목표보다 아래를 보면 + (가이드는 위로)
  final double pitchDeg;

  /// 폰이 목표보다 반시계로 돌아가면 + (가이드는 시계 방향으로)
  final double rollDeg;

  /// 화면에 보이는 장면이 오른쪽으로 밀리는 쪽이 + (가이드도 오른쪽으로)
  final double yawDeg;

  /// 각도가 맞아 프레임에 붙은 상태 (붙는 애니메이션 중일 수 있음)
  final bool locked;

  bool get isStill => pitchDeg == 0 && rollDeg == 0 && yawDeg == 0;

  /// 더 벌어져도 가이드가 화면에 남아 방향을 알려 주도록 하는 표시 한계
  static const maxTiltDeg = 25.0;
  static const maxRollDeg = 45.0;

  /// 일반 휴대폰 기본 카메라(35mm 환산 약 26mm)의 초점거리 ÷ 세로 화각 길이
  static const focalRatio = 0.75;

  /// [previewHeight]는 화면에 깔린 프리뷰 세로 길이(잘린 부분 포함).
  static double focalLength(double previewHeight, double zoom) =>
      previewHeight * focalRatio * zoom;

  /// 화면 좌표 변환. [focal]은 화면 단위 초점거리.
  Matrix4 matrix(Size screen, double focal) {
    final cx = screen.width / 2;
    final cy = screen.height / 2;
    final p = pitchDeg * math.pi / 180;
    final y = yawDeg * math.pi / 180;
    final r = rollDeg * math.pi / 180;
    final (sp, cp) = (math.sin(p), math.cos(p));
    final (sy, cy_) = (math.sin(y), math.cos(y));
    final (sr, cr) = (math.sin(r), math.cos(r));

    // R = Rz(roll) · Rx(pitch) · Ry(yaw) (카메라 좌표: x 오른쪽, y 아래, z 앞)
    // Rx·Ry
    final m = [
      [cy_, 0.0, sy],
      [sp * sy, cp, -sp * cy_],
      [-cp * sy, sp, cp * cy_],
    ];
    final rot = [
      for (var c = 0; c < 3; c++) cr * m[0][c] - sr * m[1][c],
      for (var c = 0; c < 3; c++) sr * m[0][c] + cr * m[1][c],
      for (var c = 0; c < 3; c++) m[2][c],
    ];

    // H = K · R · K⁻¹ (K: 초점거리 focal, 중심 cx·cy)
    final a = [
      for (var row = 0; row < 3; row++) ...[
        rot[row * 3] / focal,
        rot[row * 3 + 1] / focal,
        rot[row * 3 + 2] - (rot[row * 3] * cx + rot[row * 3 + 1] * cy) / focal,
      ],
    ];
    final h = [
      for (var c = 0; c < 3; c++) focal * a[c] + cx * a[6 + c],
      for (var c = 0; c < 3; c++) focal * a[3 + c] + cy * a[6 + c],
      for (var c = 0; c < 3; c++) a[6 + c],
    ];
    // 2D 호모그래피를 4x4로 (열 우선)
    return Matrix4(
      h[0],
      h[3],
      0,
      h[6], //
      h[1],
      h[4],
      0,
      h[7], //
      0,
      0,
      1,
      0, //
      h[2],
      h[5],
      0,
      h[8],
    );
  }

  /// 프레임 정규화 좌표의 레퍼런스 관절을, 움직인 가이드 위치로 옮긴다.
  List<PoseLandmark> displace(
    List<PoseLandmark> landmarks, {
    required Size screen,
    required Rect frame,
    required double focal,
  }) {
    if (isStill) return landmarks;
    final m = matrix(screen, focal);
    return [
      for (final l in landmarks)
        () {
          final p = MatrixUtils.transformPoint(
            m,
            Offset(
              frame.left + l.x * frame.width,
              frame.top + l.y * frame.height,
            ),
          );
          return PoseLandmark(
            (p.dx - frame.left) / frame.width,
            (p.dy - frame.top) / frame.height,
            l.likelihood,
          );
        }(),
    ];
  }

  @override
  bool operator ==(Object other) =>
      other is GuideMotion &&
      other.pitchDeg == pitchDeg &&
      other.rollDeg == rollDeg &&
      other.yawDeg == yawDeg &&
      other.locked == locked;

  @override
  int get hashCode => Object.hash(pitchDeg, rollDeg, yawDeg, locked);
}

/// 각도 안내 값을 부드러운 [GuideMotion]으로 바꾼다.
class GuideMotionFilter {
  /// 값이 들어올 때마다 목표로 다가가는 비율 (약 50Hz 기준 0.06초)
  static const _follow = 0.3;

  /// 좌우 회전이 이 안이면 고정, 밖이면 해제 (경계에서 깜빡이지 않게 다르게 둠)
  static const yawLockDeg = 2.0;
  static const yawReleaseDeg = 4.0;

  GuideMotion? _last;

  GuideMotion add({
    required bool angleMatched,
    required double pitchDelta,
    required double rollDelta,
    required double yawDeg,
  }) {
    final last = _last;
    final yawLimit = (last?.locked ?? false) ? yawReleaseDeg : yawLockDeg;
    final locked = angleMatched && yawDeg.abs() <= yawLimit;

    const tilt = GuideMotion.maxTiltDeg;
    const roll = GuideMotion.maxRollDeg;
    double step(double? from, double target) {
      if (from == null) return target;
      final next = from + (target - from) * _follow;
      return (next - target).abs() < 0.02 ? target : next;
    }

    return _last = GuideMotion(
      pitchDeg: step(
        last?.pitchDeg,
        locked ? 0 : pitchDelta.clamp(-tilt, tilt).toDouble(),
      ),
      rollDeg: step(
        last?.rollDeg,
        locked ? 0 : rollDelta.clamp(-roll, roll).toDouble(),
      ),
      yawDeg: step(
        last?.yawDeg,
        locked ? 0 : yawDeg.clamp(-tilt, tilt).toDouble(),
      ),
      locked: locked,
    );
  }
}
