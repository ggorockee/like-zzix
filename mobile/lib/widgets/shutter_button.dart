import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 원형 셔터. 지금 찍으면 되는 상태([ready])에서는 링이 초록색.
/// 자동 촬영 대기 중([counting])이면 링이 [countDuration] 동안 차오른다.
class ShutterButton extends StatelessWidget {
  const ShutterButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.ready = false,
    this.counting = false,
    this.countDuration = const Duration(milliseconds: 600),
  });

  final VoidCallback? onPressed;
  final bool busy;
  final bool ready;
  final bool counting;
  final Duration countDuration;

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
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ready ? AppTheme.mint : AppTheme.white,
                    width: ready ? 6 : 4,
                  ),
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
              if (counting)
                SizedBox.square(
                  dimension: 88,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: countDuration,
                    builder: (_, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 5,
                      color: AppTheme.mint,
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
