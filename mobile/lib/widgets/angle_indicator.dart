import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/attitude.dart';
import '../models/guide_motion.dart';

/// 화면 중앙 자세계: 고정된 목표 표시(원)와, 현재 기울기에 따라
/// 회전(roll)·상하 이동(pitch)하는 수평 막대. 막대가 원에 겹치면 일치.
class AngleIndicator extends StatelessWidget {
  const AngleIndicator({super.key, required this.guide, required this.focal});

  final AngleGuide guide;

  /// 화면 단위 초점거리. 막대를 레퍼런스 가이드와 같은 속도로 움직인다.
  final double focal;

  @override
  Widget build(BuildContext context) {
    final color = guide.matched ? AppTheme.mint : AppTheme.white;
    // 카메라가 목표보다 아래를 보면(+) 막대가 위로 → 폰을 위로 향하면 내려와 겹침
    const limit = GuideMotion.maxTiltDeg;
    final dy =
        -focal *
        math.tan(guide.pitchDelta.clamp(-limit, limit) * math.pi / 180);
    return IgnorePointer(
      child: SizedBox(
        width: 220,
        height: 300,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
              ),
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
                      const SizedBox(width: 44),
                      _bar(color),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(Color color) => Container(
    width: 70,
    height: 3,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
      boxShadow: const [BoxShadow(color: AppTheme.scrim, blurRadius: 4)],
    ),
  );
}

/// 하단 안내 문구: 어느 쪽으로 기울여야 하는지, 일치하면 촬영 유도.
class AngleStatus extends StatelessWidget {
  const AngleStatus({super.key, required this.guide, required this.hasPreset});

  final AngleGuide guide;
  final bool hasPreset;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = message(guide, hasPreset: hasPreset);
    final color = guide.matched ? AppTheme.mint : AppTheme.scrim;
    final onColor = guide.matched ? AppTheme.ink : AppTheme.white;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: onColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: onColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  /// 안내 문구 (테스트용으로 공개). 기울기(pitch) 안내를 수평(roll)보다 우선.
  static (IconData, String) message(
    AngleGuide guide, {
    required bool hasPreset,
  }) {
    if (!guide.upright) {
      return (Icons.stay_current_portrait, '폰을 세워서 들어 주세요');
    }
    if (guide.matched) {
      return hasPreset
          ? (Icons.check_circle, '각도 OK · 사람을 실루엣에 맞춰요')
          : (Icons.check_circle, '수평 OK');
    }
    final degrees = guide.pitchDelta.abs().round();
    return switch ((guide.tilt, guide.level)) {
      (TiltHint.aimUp, _) => (Icons.arrow_upward, '카메라를 위로 $degrees° 더 향하게'),
      (TiltHint.aimDown, _) => (
        Icons.arrow_downward,
        '카메라를 아래로 $degrees° 더 향하게',
      ),
      (_, LevelHint.rotateClockwise) => (Icons.rotate_right, '폰을 시계 방향으로 살짝'),
      (_, LevelHint.rotateCounterClockwise) => (
        Icons.rotate_left,
        '폰을 반시계 방향으로 살짝',
      ),
      _ => (Icons.straighten, '수평을 맞춰 주세요'),
    };
  }
}
