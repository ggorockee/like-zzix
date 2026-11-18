import 'package:flutter/material.dart';

import '../models/zoom_range.dart';

/// 0.5 / 1 / 2 / 3배 빠른 선택. 활성 버튼은 현재 실제 배율을 표시.
class ZoomSelector extends StatelessWidget {
  const ZoomSelector({
    super.key,
    required this.range,
    required this.zoom,
    required this.onSelected,
  });

  final ZoomRange range;
  final double zoom;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final stops = range.availableStops;
    if (stops.length < 2) return const SizedBox(height: 40);
    final active = range.activeStop(zoom);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final stop in stops)
            _ZoomButton(
              label: stop == active
                  ? ZoomRange.label(stop, current: zoom)
                  : ZoomRange.label(stop),
              active: stop == active,
              onTap: () => onSelected(stop),
            ),
        ],
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: '줌 $label',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: active ? 46 : 36,
          height: active ? 36 : 30,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? Colors.white24 : Colors.transparent,
            shape: BoxShape.rectangle,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? const Color(0xFFFFD60A) : Colors.white,
              fontSize: active ? 13 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
