import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// 서버로 보내는 익명 사용 이벤트. 이름은 서버 허용 목록과 같아야 한다
/// (server/internal/telemetry/events.go). 개인·기기 식별 정보는 보내지 않는다.
enum AppEvent {
  appOpen('app_open'),
  presetSelected('preset_selected'),
  perfectMatch('perfect_match'),
  photoSaved('photo_saved'),
  photoSaveFailed('photo_save_failed'),
  cameraUnavailable('camera_unavailable'),
  galleryOpened('gallery_opened'),
  updatePromptShown('update_prompt_shown'),
  forceUpdateShown('force_update_shown'),
  updateAccepted('update_accepted'),
  updateDismissed('update_dismissed');

  const AppEvent(this.wireName);

  final String wireName;
}

/// 이벤트를 (이름, 프리셋)별 개수로 모아 주기적으로 전송한다.
/// 전송 실패 시 개수를 유지했다가 다음에 다시 보낸다 (종류 수만큼만 쌓이므로 상한이 있음).
class TelemetryService {
  TelemetryService(
    this._api, {
    Duration flushInterval = const Duration(seconds: 30),
  }) {
    _timer = Timer.periodic(flushInterval, (_) => unawaited(flush()));
  }

  final ApiClient _api;
  late final Timer _timer;
  final Map<(String, String?), int> _pending = {};
  bool _flushing = false;

  static const _maxCount = 500;

  void record(AppEvent event, {String? preset}) {
    final key = (event.wireName, preset);
    _pending[key] = ((_pending[key] ?? 0) + 1).clamp(1, _maxCount);
  }

  @visibleForTesting
  Map<(String, String?), int> get pending => Map.unmodifiable(_pending);

  Future<void> flush() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    final batch = Map.of(_pending);
    _pending.clear();
    try {
      final ok = await _api.sendEvents([
        for (final MapEntry(key: (name, preset), value: count) in batch.entries)
          {'name': name, 'count': count, 'preset': ?preset},
      ]);
      if (!ok) _restore(batch);
    } on Object catch (e) {
      debugPrint('[Telemetry] 전송 실패, 다음에 재시도: $e');
      _restore(batch);
    } finally {
      _flushing = false;
    }
  }

  void _restore(Map<(String, String?), int> batch) {
    batch.forEach((key, count) {
      _pending[key] = ((_pending[key] ?? 0) + count).clamp(1, _maxCount);
    });
  }

  void dispose() => _timer.cancel();
}
