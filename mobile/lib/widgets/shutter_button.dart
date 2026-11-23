import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 흰 테두리 원형 셔터. 촬영 중에는 비활성화.
class ShutterButton extends StatelessWidget {
  const ShutterButton({super.key, required this.onPressed, this.busy = false});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      label: '촬영',
      child: GestureDetector(
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.5,
          child: Container(
            width: 76,
            height: 76,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.white, width: 4),
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: busy ? 0.85 : 1,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
