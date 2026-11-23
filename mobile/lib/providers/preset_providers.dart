import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/preset.dart';
import '../services/preset_repository.dart';
import '../services/telemetry_service.dart';
import 'api_providers.dart';

final presetRepositoryProvider = Provider<PresetRepository>(
  (ref) => PresetRepository(),
);

/// 벡터 구도 + 사진 프리셋.
/// 사진은 서버 목록을 우선 사용하고, 실패하거나 비어 있으면 앱 번들로 대체.
final presetsProvider = FutureProvider<List<Preset>>((ref) async {
  final repository = ref.watch(presetRepositoryProvider);
  final templates = await repository.loadTemplates();
  final bundled = await repository.loadBundled();
  final api = ref.watch(apiClientProvider);
  if (api != null) {
    try {
      final raw = await api.fetchPresets();
      final remote = raw == null
          ? const <Preset>[]
          : PresetRepository.parse(raw);
      if (remote.isNotEmpty) {
        final ids = {for (final t in templates) t.id};
        return PresetRepository.merge(templates, [
          // 구도 사진이 아직 등록되지 않은 서버면 번들 사진으로
          if (!remote.any((p) => ids.contains(p.id))) ...bundled,
          for (final p in remote) p.withBundledPhoto(bundled),
        ]);
      }
    } on Object catch (e) {
      debugPrint('[Preset] 서버 목록 실패, 번들 사용: $e');
    }
  }
  return PresetRepository.merge(templates, bundled);
});

/// 시트에서 고른 프리셋 (반전 전 원본). null이면 가이드 없음.
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

/// 좌우 반전. 프리셋을 바꾸면 해제.
final guideMirrorProvider = NotifierProvider<GuideMirrorNotifier, bool>(
  GuideMirrorNotifier.new,
);

class GuideMirrorNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(selectedPresetProvider);
    return false;
  }

  void toggle() => state = !state;
}

/// 화면에 보이는 프리셋 (반전 적용).
final activePresetProvider = Provider<Preset?>((ref) {
  final preset = ref.watch(selectedPresetProvider);
  return ref.watch(guideMirrorProvider) ? preset?.flipped : preset;
});

/// 가이드 진하기 (0~1). 기본값은 실루엣 12%(아주 흐리게), 사진 40%.
/// 사용자가 바꾸면 종류별로 저장해 다음에도 쓴다.
final overlayOpacityProvider = NotifierProvider<OverlayOpacityNotifier, double>(
  OverlayOpacityNotifier.new,
);

class OverlayOpacityNotifier extends Notifier<double> {
  static const min = 0.0;
  static const max = 1.0;
  static const silhouetteDefault = 0.12;
  static const photoDefault = 0.4;

  static String _key(bool isTemplate) =>
      isTemplate ? 'silhouette_opacity' : 'photo_opacity';

  @override
  double build() {
    final isTemplate = ref.watch(
      selectedPresetProvider.select((p) => p?.isTemplate ?? true),
    );
    unawaited(_restore(isTemplate));
    return isTemplate ? silhouetteDefault : photoDefault;
  }

  Future<void> _restore(bool isTemplate) async {
    try {
      final store = await SharedPreferences.getInstance();
      final saved = store.getDouble(_key(isTemplate));
      if (saved != null && ref.mounted) state = saved.clamp(min, max);
    } on Object catch (e) {
      debugPrint('[Opacity] 저장 값 읽기 실패: $e');
    }
  }

  void set(double value) {
    state = value.clamp(min, max);
    final isTemplate = ref.read(selectedPresetProvider)?.isTemplate ?? true;
    unawaited(
      SharedPreferences.getInstance().then(
        (s) => s.setDouble(_key(isTemplate), state),
        onError: (Object e) {
          debugPrint('[Opacity] 저장 실패: $e');
          return false;
        },
      ),
    );
  }
}
