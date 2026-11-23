import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/pose_match.dart';
import '../models/preset.dart';
import 'reference_image.dart';
import 'silhouette_painter.dart';

/// 카메라 위에 겹치는 레퍼런스: 원본 사진(반투명) + 인물 외곽선 + 실시간 관절 점.
///
/// 사진·외곽선·관절 모두 같은 프레임 영역([SilhouettePainter.frameRect]) 기준.
class ReferenceOverlay extends StatelessWidget {
  const ReferenceOverlay({
    super.key,
    required this.preset,
    required this.opacity,
    this.match,
    this.live,
    this.perfect = false,
  });

  final Preset preset;
  final double opacity;
  final PoseMatchResult? match;
  final List<PoseLandmark>? live;
  final bool perfect;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final frame = SilhouettePainter.frameRect(
            constraints.biggest,
            preset.aspectRatio,
          );
          return Stack(
            children: [
              Positioned.fromRect(
                rect: frame,
                child: Opacity(
                  opacity: opacity,
                  child: ReferenceImage(
                    preset: preset,
                    fit: BoxFit.fill,
                    showFallback: false,
                  ),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: SilhouettePainter(
                    preset: preset,
                    color: perfect ? AppTheme.mint : AppTheme.white,
                    strokeWidth: perfect ? 4 : 3,
                    fillOpacity: 0,
                  ),
                ),
              ),
              if (live != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: LiveJointsPainter(
                      live: live!,
                      jointOk: match?.jointOk ?? const {},
                      aspectRatio: preset.aspectRatio,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 실시간으로 인식된 관절 점. 목표 위치 근처면 초록, 아니면 주황.
class LiveJointsPainter extends CustomPainter {
  const LiveJointsPainter({
    required this.live,
    required this.jointOk,
    required this.aspectRatio,
  });

  final List<PoseLandmark> live;
  final Map<int, bool> jointOk;
  final double aspectRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = SilhouettePainter.frameRect(size, aspectRatio);
    final outline = Paint()
      ..color = AppTheme.scrim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final j in PoseMatcher.joints) {
      if (j >= live.length || !live[j].isVisible) continue;
      final c = Offset(
        frame.left + live[j].x * frame.width,
        frame.top + live[j].y * frame.height,
      );
      final ok = jointOk[j];
      final color = ok == null
          ? AppTheme.whiteMuted
          : ok
          ? AppTheme.mint
          : AppTheme.coral;
      canvas
        ..drawCircle(c, 6, Paint()..color = color)
        ..drawCircle(c, 6, outline);
    }
  }

  @override
  bool shouldRepaint(LiveJointsPainter old) =>
      old.live != live ||
      old.jointOk != jointOk ||
      old.aspectRatio != aspectRatio;
}
