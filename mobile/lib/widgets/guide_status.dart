import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/attitude.dart';
import '../models/pose_match.dart';
import '../providers/pose_providers.dart';
import 'angle_indicator.dart';

enum GuideTone { neutral, good, perfect }

/// 하단 안내 문구: 각도 + 구도(포즈) 중 지금 가장 먼저 고칠 것 하나만 보여준다.
class GuideStatus extends StatelessWidget {
  const GuideStatus({
    super.key,
    required this.angle,
    required this.pose,
    required this.hasPreset,
  });

  final AngleGuide? angle;
  final PoseMatchState? pose;
  final bool hasPreset;

  @override
  Widget build(BuildContext context) {
    final message = GuideStatus.message(
      angle: angle,
      pose: pose,
      hasPreset: hasPreset,
    );
    if (message == null) return const SizedBox(height: 36);
    final (icon, text, tone) = message;
    final color = switch (tone) {
      GuideTone.perfect => AppTheme.matchGreen,
      GuideTone.good => AppTheme.matchGreen.withValues(alpha: 0.75),
      GuideTone.neutral => Colors.black54,
    };
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
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 우선순위: Perfect → 폰 세우기 → 사람 인식 → 몸 보이기 → 각도 → 거리/위치 → 포즈.
  static (IconData, String, GuideTone)? message({
    required AngleGuide? angle,
    required PoseMatchState? pose,
    required bool hasPreset,
  }) {
    if (pose?.perfect ?? false) {
      return (Icons.photo_camera, '지금 찍으세요!', GuideTone.perfect);
    }
    (IconData, String, GuideTone)? angleMessage() {
      if (angle == null) return null;
      final (icon, text) = AngleStatus.message(angle, hasPreset: hasPreset);
      return (icon, text, angle.matched ? GuideTone.good : GuideTone.neutral);
    }

    if (angle != null && !angle.upright) return angleMessage();
    if (!hasPreset || pose == null) return angleMessage();

    final result = pose.result;
    switch (result.hint) {
      case PoseHint.noPerson:
        return (Icons.person_search, '사람이 화면에 보이게 해 주세요', GuideTone.neutral);
      case PoseHint.showMoreBody:
        return (
          Icons.accessibility_new,
          '레퍼런스처럼 몸이 더 보이게 해 주세요',
          GuideTone.neutral,
        );
      default:
        break;
    }
    if (angle != null && !angle.matched) return angleMessage();

    return switch (result.hint) {
      PoseHint.stepCloser => (Icons.zoom_in, '다가가거나 줌을 올려요', GuideTone.neutral),
      PoseHint.stepBack => (Icons.zoom_out, '물러나거나 줌을 내려요', GuideTone.neutral),
      PoseHint.panRight => (
        Icons.arrow_forward,
        '카메라를 오른쪽으로 살짝',
        GuideTone.neutral,
      ),
      PoseHint.panLeft => (Icons.arrow_back, '카메라를 왼쪽으로 살짝', GuideTone.neutral),
      PoseHint.lowerPhone => (Icons.south, '폰 높이를 조금 낮춰요', GuideTone.neutral),
      PoseHint.raisePhone => (Icons.north, '폰 높이를 조금 올려요', GuideTone.neutral),
      PoseHint.adjustPose => (
        Icons.accessibility_new,
        '포즈를 레퍼런스처럼 맞춰요 · ${result.score}%',
        GuideTone.neutral,
      ),
      PoseHint.matched => (Icons.check_circle, '좋아요, 그대로!', GuideTone.good),
      PoseHint.noPerson || PoseHint.showMoreBody => angleMessage(),
    };
  }
}

/// Perfect Match 시 화면 중앙 상단에 크게 띄우는 배너.
class PerfectMatchBanner extends StatelessWidget {
  const PerfectMatchBanner({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedScale(
        scale: visible ? 1 : 0.8,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.matchGreen,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 12),
              ],
            ),
            child: const Text(
              '지금 찍으세요!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
