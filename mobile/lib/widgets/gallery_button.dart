import 'dart:io';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 최근 촬영 사진 썸네일. 탭하면 기기 갤러리 앱으로 이동.
class GalleryButton extends StatelessWidget {
  const GalleryButton({
    super.key,
    required this.lastPhotoPath,
    required this.onTap,
  });

  final String? lastPhotoPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final path = lastPhotoPath;
    return Tooltip(
      message: '갤러리',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Container(
            key: ValueKey(path),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.scrim,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.white, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: path == null
                ? const Icon(Icons.photo_library_outlined, size: 22)
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 144,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.photo_library_outlined, size: 22),
                  ),
          ),
        ),
      ),
    );
  }
}
