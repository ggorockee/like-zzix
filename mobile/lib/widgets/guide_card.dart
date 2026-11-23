import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/preset.dart';

/// 선택한 프리셋의 촬영 팁 + 단계별 가이드 (탭하면 접기/펼치기).
class GuideCard extends StatefulWidget {
  const GuideCard({super.key, required this.preset});

  final Preset preset;

  @override
  State<GuideCard> createState() => _GuideCardState();
}

class _GuideCardState extends State<GuideCard> {
  bool _expanded = true;

  @override
  void didUpdateWidget(GuideCard old) {
    super.didUpdateWidget(old);
    // 다른 프리셋을 고르면 다시 펼쳐서 보여준다.
    if (old.preset != widget.preset) _expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final text = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: AppTheme.scrim,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(preset.tip, style: text.bodySmall),
              if (_expanded && preset.guide.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final (i, step) in preset.guide.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          alignment: Alignment.center,
                          margin: const EdgeInsets.only(right: 8, top: 1),
                          decoration: const BoxDecoration(
                            color: AppTheme.whiteFaint,
                            shape: BoxShape.circle,
                          ),
                          child: Text('${i + 1}', style: text.labelSmall),
                        ),
                        Expanded(child: Text(step, style: text.bodySmall)),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
