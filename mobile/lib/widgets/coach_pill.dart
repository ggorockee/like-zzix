import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/coach.dart';

/// 하단 코칭 문구: 지금 할 행동 하나만.
class CoachPill extends StatelessWidget {
  const CoachPill({super.key, required this.message});

  final CoachMessage? message;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message == null) return const SizedBox(height: 40);
    final (background, foreground) = switch (message.tone) {
      CoachTone.perfect => (AppTheme.mint, AppTheme.ink),
      CoachTone.warning => (AppTheme.amber, AppTheme.ink),
      CoachTone.neutral => (AppTheme.scrim, AppTheme.white),
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(message.icon, size: 20, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message.text,
              style: TextStyle(
                color: foreground,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
