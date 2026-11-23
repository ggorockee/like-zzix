import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_theme.dart';

/// 가이드 잠금. 한 번 누르면 잠기고, 풀려면 [holdDuration] 동안 길게 눌러야 한다.
class LockButton extends StatefulWidget {
  const LockButton({
    super.key,
    required this.locked,
    required this.onLock,
    required this.onUnlock,
  });

  static const holdDuration = Duration(milliseconds: 800);

  final bool locked;

  /// null이면 비활성 (고른 가이드가 없음)
  final VoidCallback? onLock;
  final VoidCallback onUnlock;

  @override
  State<LockButton> createState() => _LockButtonState();
}

class _LockButtonState extends State<LockButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold =
      AnimationController(vsync: this, duration: LockButton.holdDuration)
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _hold.value = 0;
          HapticFeedback.mediumImpact();
          widget.onUnlock();
        });

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _release() {
    if (_hold.status != AnimationStatus.completed) _hold.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.locked;
    final enabled = locked || widget.onLock != null;
    return Semantics(
      button: true,
      label: locked ? '가이드 잠금 해제, 길게 누르기' : '가이드 잠금',
      onTap: locked ? null : widget.onLock,
      onLongPress: locked ? widget.onUnlock : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: locked ? null : widget.onLock,
        onTapDown: locked ? (_) => _hold.forward(from: 0) : null,
        onTapUp: locked ? (_) => _release() : null,
        onTapCancel: locked ? _release : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.4,
          child: SizedBox.square(
            dimension: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: locked ? AppTheme.coral : AppTheme.scrim,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    locked ? Icons.lock : Icons.lock_open,
                    color: locked ? AppTheme.ink : AppTheme.white,
                  ),
                ),
                AnimatedBuilder(
                  animation: _hold,
                  builder: (_, _) => _hold.value == 0
                      ? const SizedBox.shrink()
                      : SizedBox.square(
                          dimension: 56,
                          child: CircularProgressIndicator(
                            value: _hold.value,
                            strokeWidth: 4,
                            color: AppTheme.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
