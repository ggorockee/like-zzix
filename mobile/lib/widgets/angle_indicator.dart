import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/angle_state.dart';
import '../models/guide_motion.dart';

/// 화면 중앙: 고정 기준선(원 + 짧은 선)과, 기울기에 따라 움직이는 수평 막대.
/// 각도가 벗어나면 노란색 + 방향 화살표, 맞으면 초록색.
class AngleIndicator extends StatelessWidget {
  const AngleIndicator({super.key, required this.guide, required this.focal});

  final AngleGuide guide;

  /// 화면 단위 초점거리. 막대를 가이드와 같은 속도로 움직인다.
  final double focal;

  @override
  Widget build(BuildContext context) {
    final color = switch (guide.state) {
      AngleState.waiting => AppTheme.whiteMuted,
      AngleState.off => AppTheme.amber,
      AngleState.good => AppTheme.mint,
    };
    // 카메라가 목표보다 아래를 보면(+) 막대가 위로 → 폰을 위로 향하면 내려와 겹침
    const limit = GuideMotion.maxTiltDeg;
    final dy =
        -focal *
        math.tan(guide.pitchDelta.clamp(-limit, limit) * math.pi / 180);
    return IgnorePointer(
      child: SizedBox(
        width: 240,
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 고정 기준선
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _bar(AppTheme.whiteMuted, width: 18, height: 2),
                const SizedBox(width: 6),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
                const SizedBox(width: 6),
                _bar(AppTheme.whiteMuted, width: 18, height: 2),
              ],
            ),
            // 폰이 눕혀져 있으면 수평 막대는 의미가 없으므로 숨김
            if (guide.upright)
              Transform.translate(
                offset: Offset(0, dy),
                child: Transform.rotate(
                  // 화면에 보이는 실제 수평선 방향 (폰이 반시계로 돌면 시계 방향)
                  angle: guide.rollDelta * math.pi / 180,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _bar(color),
                      const SizedBox(width: 92),
                      _bar(color),
                    ],
                  ),
                ),
              ),
            if (_hint case (final icon, final offset)?)
              Transform.translate(
                offset: offset,
                child: Icon(
                  icon,
                  size: 30,
                  color: AppTheme.amber,
                  shadows: const [Shadow(color: AppTheme.ink, blurRadius: 5)],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 폰을 움직일 방향 화살표와 놓일 자리.
  (IconData, Offset)? get _hint => switch ((guide.tilt, guide.level)) {
    (TiltHint.aimUp, _) => (
      Icons.keyboard_double_arrow_up,
      const Offset(0, -42),
    ),
    (TiltHint.aimDown, _) => (
      Icons.keyboard_double_arrow_down,
      const Offset(0, 42),
    ),
    (_, LevelHint.rotateClockwise) => (
      Icons.rotate_right,
      const Offset(0, -42),
    ),
    (_, LevelHint.rotateCounterClockwise) => (
      Icons.rotate_left,
      const Offset(0, -42),
    ),
    _ => null,
  };

  Widget _bar(Color color, {double width = 60, double height = 3}) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
      boxShadow: const [BoxShadow(color: AppTheme.scrim, blurRadius: 4)],
    ),
  );
}
