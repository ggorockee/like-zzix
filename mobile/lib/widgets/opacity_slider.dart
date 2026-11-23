import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../providers/preset_providers.dart';

/// 가이드 진하기 조절 (상단 반투명 캡슐). 0이면 숨김.
class OpacitySlider extends StatelessWidget {
  const OpacitySlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = '실루엣',
  });

  final double value;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.scrimSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.opacity, size: 18),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: AppTheme.white,
                inactiveTrackColor: AppTheme.whiteFaint,
                thumbColor: AppTheme.white,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value,
                min: OverlayOpacityNotifier.min,
                max: OverlayOpacityNotifier.max,
                semanticFormatterCallback: (v) =>
                    '$label 진하기 ${(v * 100).round()}%',
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
