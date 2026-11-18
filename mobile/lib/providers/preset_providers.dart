import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/preset.dart';
import '../services/preset_repository.dart';

final presetRepositoryProvider = Provider<PresetRepository>(
  (ref) => PresetRepository(),
);

final presetsProvider = FutureProvider<List<Preset>>(
  (ref) => ref.watch(presetRepositoryProvider).loadBundled(),
);

/// 현재 선택된 프리셋. null이면 실루엣 오버레이 없음.
final selectedPresetProvider =
    NotifierProvider<SelectedPresetNotifier, Preset?>(
      SelectedPresetNotifier.new,
    );

class SelectedPresetNotifier extends Notifier<Preset?> {
  @override
  Preset? build() => null;

  /// 같은 프리셋을 다시 고르면 선택 해제.
  void toggle(Preset preset) => state = state == preset ? null : preset;

  void clear() => state = null;
}

/// 실루엣 투명도 (0.1~1.0).
final overlayOpacityProvider = NotifierProvider<OverlayOpacityNotifier, double>(
  OverlayOpacityNotifier.new,
);

class OverlayOpacityNotifier extends Notifier<double> {
  static const min = 0.1;
  static const max = 1.0;

  @override
  double build() => 0.7;

  void set(double value) => state = value.clamp(min, max);
}
