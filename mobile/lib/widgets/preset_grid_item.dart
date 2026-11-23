import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/preset.dart';
import 'reference_image.dart';

/// 프리셋 그리드 칸: 레퍼런스 사진(없으면 실루엣) + 제목. 선택 시 브랜드 색 테두리.
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
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: AppTheme.inkRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppTheme.coral : Colors.transparent,
              width: 2.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ReferenceImage(preset: preset),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.center,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, AppTheme.scrimStrong],
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Text(
                  preset.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AppTheme.white,
                    fontWeight: FontWeight.w600,
                  ),
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
          border: Border.all(color: AppTheme.whiteFaint),
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
