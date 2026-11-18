import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/preset.dart';
import 'silhouette_painter.dart';

/// 프리셋 그리드 칸: 실루엣 미리보기 + 제목. 선택 시 브랜드 색 테두리.
class PresetGridItem extends StatelessWidget {
  const PresetGridItem({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final Preset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.title} 프리셋',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.brand : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: SilhouettePainter(
                      landmarks: preset.landmarks,
                      aspectRatio: preset.aspectRatio,
                      color: Colors.white70,
                      strokeWidth: 1.6,
                      dashed: false,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(
                  preset.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 그리드 첫 칸: 갤러리 사진으로 커스텀 실루엣 만들기 (M3에서 연결).
class CreateFromPhotoItem extends StatelessWidget {
  const CreateFromPhotoItem({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 32),
            SizedBox(height: 8),
            Text('내 사진으로\n만들기', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
