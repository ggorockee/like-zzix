import 'package:flutter/material.dart';

import '../models/preset.dart';
import 'silhouette_painter.dart';

/// 프리셋 레퍼런스 사진. 사진이 없는 빌드(공개 저장소 clone 등)에서는 실루엣으로 대체.
class ReferenceImage extends StatelessWidget {
  const ReferenceImage({
    super.key,
    required this.preset,
    this.fit = BoxFit.cover,
    this.silhouetteStroke = 1.6,
  });

  final Preset preset;
  final BoxFit fit;
  final double silhouetteStroke;

  @override
  Widget build(BuildContext context) {
    final fallback = CustomPaint(
      size: Size.infinite,
      painter: SilhouettePainter(
        preset: preset,
        color: Colors.white,
        strokeWidth: silhouetteStroke,
        glow: false,
        fillOpacity: 0.15,
      ),
    );
    final asset = preset.referenceAsset;
    if (asset == null) return fallback;
    return Image.asset(
      asset,
      fit: fit,
      // 축소본 기준으로 디코딩해 메모리 절약
      cacheWidth: 540,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
