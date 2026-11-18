import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 카메라 프리뷰 좌표 → 화면 → 프리셋 프레임 좌표 변환.
///
/// 프리뷰는 화면을 꽉 채우도록(cover) 확대되어 일부가 잘리므로,
/// 레퍼런스(프레임 기준 0~1)와 비교하려면 같은 변환을 거쳐야 한다.
@immutable
class PreviewTransform {
  const PreviewTransform({
    required this.screen,
    required this.previewAspect,
    required this.frame,
  });

  /// 화면(위젯) 크기
  final Size screen;

  /// 세로 화면 기준 프리뷰 가로/세로 비율 (예: 720x1280 → 0.5625)
  final double previewAspect;

  /// 화면 안의 프리셋 프레임 영역
  final Rect frame;

  /// cover로 배치된 프리뷰가 화면에서 차지하는 영역 (화면 밖으로 넘칠 수 있음).
  Rect get previewRect {
    var width = screen.width;
    var height = width / previewAspect;
    if (height < screen.height) {
      height = screen.height;
      width = height * previewAspect;
    }
    return Rect.fromLTWH(
      (screen.width - width) / 2,
      (screen.height - height) / 2,
      width,
      height,
    );
  }

  /// 프리뷰 정규화 좌표(0~1) → 화면 좌표
  Offset toScreen(Offset previewNormalized) {
    final r = previewRect;
    return Offset(
      r.left + previewNormalized.dx * r.width,
      r.top + previewNormalized.dy * r.height,
    );
  }

  /// 프리뷰 정규화 좌표(0~1) → 프레임 정규화 좌표 (프레임 밖이면 0~1을 벗어남)
  Offset toFrame(Offset previewNormalized) {
    final s = toScreen(previewNormalized);
    return Offset(
      (s.dx - frame.left) / frame.width,
      (s.dy - frame.top) / frame.height,
    );
  }
}
