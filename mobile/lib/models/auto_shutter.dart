import 'dart:async';

import 'package:flutter/foundation.dart';

/// 자동 촬영: 초록불이 [hold]만큼 이어지면 한 번 촬영한다.
///
/// 한 번 찍은 뒤에는 초록불이 꺼졌다 다시 켜져야 또 찍는다 (연속 촬영 방지).
class AutoShutter {
  AutoShutter({
    required this.onFire,
    this.hold = const Duration(milliseconds: 600),
  });

  final VoidCallback onFire;
  final Duration hold;

  /// 초록불 유지 시간을 세는 중 (셔터 진행 링 표시용)
  final ValueNotifier<bool> counting = ValueNotifier(false);

  Timer? _timer;
  bool _fired = false;

  /// [ready]는 초록불, [enabled]는 켜짐 여부와 촬영 가능 여부(촬영 중·시트 열림이면 false).
  void update({required bool ready, required bool enabled}) {
    if (!ready) _fired = false;
    if (!ready || !enabled) {
      _stop();
      return;
    }
    if (_fired || _timer != null) return;
    counting.value = true;
    _timer = Timer(hold, () {
      _stop();
      _fired = true;
      onFire();
    });
  }

  /// 다른 방법으로 찍었을 때: 이번 초록불에서는 자동으로 또 찍지 않는다.
  void markShot() {
    _stop();
    _fired = true;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    counting.value = false;
  }

  void dispose() {
    _timer?.cancel();
    counting.dispose();
  }
}
