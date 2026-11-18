import 'package:flutter/material.dart';

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
          barrierColor: Colors.black87,
          builder: (context) => GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: AspectRatio(
                aspectRatio: preset.aspectRatio,
                child: ReferenceImage(
                  preset: preset,
                  fit: BoxFit.contain,
                  silhouetteStroke: 3,
                ),
              ),
            ),
          ),
        ),
        child: Container(
          width: 84,
          height: 84 / preset.aspectRatio,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 6)],
          ),
          clipBehavior: Clip.antiAlias,
          child: ColoredBox(
            color: const Color(0xFF2A2A2E),
            child: ReferenceImage(preset: preset),
          ),
        ),
      ),
    );
  }
}
