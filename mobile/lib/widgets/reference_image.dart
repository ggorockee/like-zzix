import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/env.dart';
import '../models/preset.dart';
import 'silhouette_painter.dart';

/// 프리셋 레퍼런스 사진. 사진이 없는 빌드(공개 저장소 clone 등)에서는 실루엣으로 대체.
class ReferenceImage extends StatelessWidget {
  const ReferenceImage({
    super.key,
    required this.preset,
    this.fit = BoxFit.cover,
    this.silhouetteStroke = 1.6,
    this.showFallback = true,
  });

  final Preset preset;
  final BoxFit fit;
  final double silhouetteStroke;

  /// 사진이 없을 때 실루엣으로 대체할지 (오버레이처럼 외곽선을 따로 그리는 곳은 false)
  final bool showFallback;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = !showFallback
        ? const SizedBox.shrink()
        : CustomPaint(
            size: Size.infinite,
            painter: SilhouettePainter(
              // 아래에서 통째로 뒤집으므로 원래 방향으로 그린다
              preset: preset.mirrored ? preset.flipped : preset,
              color: AppTheme.white,
              strokeWidth: silhouetteStroke,
              fillOpacity: 0.15,
            ),
          );
    final Widget local = preset.referenceAsset == null
        ? fallback
        : Image.asset(
            preset.referenceAsset!,
            fit: fit,
            // 축소본 기준으로 디코딩해 메모리 절약
            cacheWidth: 540,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => fallback,
          );
    // 관리자 콘솔에서 올린 사진이 있으면 우선 사용, 못 받으면 번들 사진 → 실루엣
    final url = resolveReferenceUrl(preset.referenceUrl, Env.apiBaseUrl);
    final Widget image = url == null
        ? local
        : Image.network(
            url,
            fit: fit,
            cacheWidth: 540,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => local,
          );
    return preset.mirrored ? Transform.flip(flipX: true, child: image) : image;
  }
}

/// 서버가 준 상대 경로를 API 주소 기준 절대 URL로. API 주소가 없는 빌드면 null.
String? resolveReferenceUrl(String? path, String apiBaseUrl) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (apiBaseUrl.isEmpty) return null;
  return Uri.parse(apiBaseUrl).resolve(path).toString();
}
