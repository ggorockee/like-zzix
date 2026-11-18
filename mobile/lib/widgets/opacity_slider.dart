import 'package:flutter/material.dart';

import '../providers/preset_providers.dart';

/// 실루엣 투명도 조절 (상단 반투명 캡슐).
class OpacitySlider extends StatelessWidget {
  const OpacitySlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.opacity, size: 18),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(
                value: value,
                min: OverlayOpacityNotifier.min,
                max: OverlayOpacityNotifier.max,
                semanticFormatterCallback: (v) =>
                    '실루엣 투명도 ${(v * 100).round()}%',
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
