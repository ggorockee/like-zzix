import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/preset.dart';
import 'reference_image.dart';

/// 우측 상단 레퍼런스 사진 미리보기. 탭하면 크게 보기.
class ReferencePip extends StatelessWidget {
  const ReferencePip({super.key, required this.preset});

  final Preset preset;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '레퍼런스 크게 보기',
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: AppTheme.scrimStrong,
          builder: (context) => GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: AspectRatio(
                aspectRatio: preset.aspectRatio,
                child: ReferenceImage(preset: preset, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        child: Container(
          width: 84,
          height: 84 / preset.aspectRatio,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.white, width: 2),
            boxShadow: const [BoxShadow(color: AppTheme.scrim, blurRadius: 6)],
          ),
          clipBehavior: Clip.antiAlias,
          child: ColoredBox(
            color: AppTheme.inkRaised,
            child: ReferenceImage(preset: preset),
          ),
        ),
      ),
    );
  }
}
