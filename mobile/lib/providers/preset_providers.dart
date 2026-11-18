import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import '../services/preset_repository.dart';
import '../services/telemetry_service.dart';
import 'api_providers.dart';

final presetRepositoryProvider = Provider<PresetRepository>(
  (ref) => PresetRepository(),
);

/// 서버 목록을 우선 사용하고, 실패하거나 비어 있으면 앱 번들 프리셋으로 대체.
final presetsProvider = FutureProvider<List<Preset>>((ref) async {
  final repository = ref.watch(presetRepositoryProvider);
  final api = ref.watch(apiClientProvider);
  if (api != null) {
    try {
      final raw = await api.fetchPresets();
      final remote = raw == null
          ? const <Preset>[]
          : PresetRepository.parse(raw);
      if (remote.isNotEmpty) return remote;
    } on Object catch (e) {
      debugPrint('[Preset] 서버 목록 실패, 번들 사용: $e');
    }
  }
  return repository.loadBundled();
});

/// 현재 선택된 프리셋. null이면 실루엣 오버레이 없음.
final selectedPresetProvider =
    NotifierProvider<SelectedPresetNotifier, Preset?>(
      SelectedPresetNotifier.new,
    );

class SelectedPresetNotifier extends Notifier<Preset?> {
  @override
  Preset? build() => null;

  /// 같은 프리셋을 다시 고르면 선택 해제.
  void toggle(Preset preset) {
    state = state == preset ? null : preset;
    if (state != null) {
      ref
          .read(telemetryProvider)
          ?.record(AppEvent.presetSelected, preset: preset.id);
    }
  }

  void clear() => state = null;
}

/// 레퍼런스 사진 오버레이 투명도 (0.1~1.0, 기본 40%).
final overlayOpacityProvider = NotifierProvider<OverlayOpacityNotifier, double>(
  OverlayOpacityNotifier.new,
);

class OverlayOpacityNotifier extends Notifier<double> {
  static const min = 0.1;
  static const max = 1.0;

  @override
  double build() => 0.4;

  void set(double value) => state = value.clamp(min, max);
}
