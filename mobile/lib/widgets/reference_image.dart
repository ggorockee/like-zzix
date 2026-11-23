import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/env.dart';
import '../models/preset.dart';

/// 구도의 예시 사진. 관리자 콘솔 사진 → 번들 사진 → 빈 자리 순으로 보여 준다.
class ReferenceImage extends StatelessWidget {
  const ReferenceImage({
    super.key,
    required this.preset,
    this.fit = BoxFit.cover,
  });

  final Preset preset;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(
      color: AppTheme.inkRaised,
      child: Center(
        child: Icon(Icons.image_outlined, color: AppTheme.whiteFaint),
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
    final url = resolveReferenceUrl(preset.referenceUrl, Env.apiBaseUrl);
    final Widget image = url == null
        ? local
        : Image.network(
            url,
            fit: fit,
            cacheWidth: 540,
            gaplessPlayback: true,
            // 받는 동안에도 번들 사진을 보여 빈 칸이 없게 한다
            frameBuilder: (context, child, frame, sync) =>
                sync || frame != null ? child : local,
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
