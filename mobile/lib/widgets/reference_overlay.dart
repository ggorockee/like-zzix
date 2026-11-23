import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/guide_motion.dart';
import '../models/preset.dart';
import '../models/subject.dart';
import 'reference_image.dart';
import 'silhouette_painter.dart';
import 'template_painter.dart';

/// 고스트: 처음 위치를 잡을 때만 잠깐 보이는 반투명 실루엣(또는 레퍼런스 사진).
/// 사람이 인식되면 [visible]이 꺼지며 스르륵 사라지고, 동적 프레임이 이어받는다.
///
/// 권장 각도에서 벗어난 만큼([motion]) 실제 장면처럼 움직인다.
class ReferenceOverlay extends StatelessWidget {
  const ReferenceOverlay({
    super.key,
    required this.preset,
    required this.opacity,
    required this.visible,
    this.motion = GuideMotion.still,
    this.focal = 1,
  });

  final Preset preset;
  final double opacity;
  final bool visible;
  final GuideMotion motion;

  /// 화면 단위 초점거리 ([GuideMotion.focalLength])
  final double focal;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        child: LayoutBuilder(
          builder: (context, constraints) => Transform(
            transform: motion.matrix(constraints.biggest, focal),
            // 움직이는 동안 그림은 다시 그리지 않고 변환만 바꾼다
            child: RepaintBoundary(
              child: Stack(
                children: _layers(
                  SubjectTarget.fitFrame(
                    constraints.biggest,
                    preset.aspectRatio,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _layers(Rect frame) {
    if (preset.template case final template?) {
      return [
        Positioned.fill(
          child: CustomPaint(
            painter: TemplatePainter(
              template: template,
              color: AppTheme.white.withValues(alpha: opacity),
              strokeWidth: 1.8,
              // 보조선은 격자 층에서 촬영 직전까지 계속 보여 준다
              showGuides: false,
            ),
          ),
        ),
      ];
    }
    return [
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
            color: AppTheme.white,
            strokeWidth: 1.8,
            fillOpacity: 0,
          ),
        ),
      ),
    ];
  }
}
