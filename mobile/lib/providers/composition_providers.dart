import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/composition_fit.dart';
import '../models/subject.dart';
import 'camera_providers.dart';
import 'preset_providers.dart';

/// 화면 속 사람들과 구도의 현재 상태.
@immutable
class CompositionState {
  const CompositionState({
    required this.targets,
    required this.fit,
    this.fits = false,
  });

  final List<Target> targets;
  final CompositionFit fit;

  /// 구도 일치 (90점 이상 진입, 86점 미만 이탈, [CompositionController.holdDuration] 유지)
  final bool fits;

  bool get hasPerson => fit.hasPerson;
}

/// 현재 시각 (테스트에서 교체).
final visionClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 실시간 구도 판정 Controller. 카메라 화면이 인식 프레임마다 [update]를 부른다.
final compositionProvider =
    NotifierProvider<CompositionController, CompositionState?>(
      CompositionController.new,
    );

/// 자리 하나를 차지한 사람의 추적 상태.
class _Track {
  LivePerson? person;
  DateTime? seenAt;
}

class CompositionController extends Notifier<CompositionState?> {
  /// 일치로 인정하기까지 유지해야 하는 시간
  static const holdDuration = Duration(milliseconds: 250);

  /// 인식이 잠깐 끊겨도 사람이 있는 것으로 보는 시간
  static const lostGrace = Duration(milliseconds: 500);

  /// 안내 문구가 너무 빨리 바뀌지 않게 하는 최소 유지 시간
  static const actionDwell = Duration(milliseconds: 450);

  /// 위치·크기 로우패스 시간 상수(초)
  static const _smoothTau = 0.12;

  List<_Track> _tracks = const [];
  DateTime? _updatedAt;
  DateTime? _matchedAt;
  DateTime? _actionAt;
  bool _entered = false;

  @override
  CompositionState? build() {
    ref.watch(activePresetProvider);
    _reset();
    return null;
  }

  void _reset() {
    _tracks = const [];
    _updatedAt = _matchedAt = _actionAt = null;
    _entered = false;
  }

  void clear() {
    _reset();
    state = null;
  }

  /// [people]은 이번 프레임에서 찾은 사람들, [focal]은 화면 단위 초점거리.
  void update(
    List<LivePerson> people,
    List<Target> targets, {
    required double focal,
  }) {
    if (targets.isEmpty) return;
    final now = ref.read(visionClockProvider)();
    final dt = _updatedAt == null
        ? 0.0
        : now.difference(_updatedAt!).inMicroseconds / 1e6;
    _updatedAt = now;
    if (_tracks.length != targets.length) {
      _tracks = [for (final _ in targets) _Track()];
    }

    // 1) 자리마다 사람을 배정하고 떨림을 줄인다
    final found = CompositionFit.assign(targets, people);
    final gain = 1 - math.exp(-dt / _smoothTau);
    for (final (i, track) in _tracks.indexed) {
      final person = found[i];
      if (person != null) {
        track
          ..person = track.person?.lerpTo(person, gain) ?? person
          ..seenAt = now;
      } else if (track.seenAt == null ||
          now.difference(track.seenAt!) > lostGrace) {
        track.person = null;
      }
    }

    // 2) 판정. 화면 비율이 바뀌었으면 이전 결과를 쓰지 않는다
    final last = state;
    final sameLayout =
        last != null &&
        last.targets.length == targets.length &&
        last.targets.first.center == targets.first.center;
    final fit = CompositionFit.evaluateAssigned(
      targets,
      [for (final t in _tracks) t.person],
      focal: focal,
      previous: sameLayout
          ? [for (final t in last.fit.targets) t.hits]
          : const [],
    );

    // 3) 히스테리시스(진입 엄격 / 이탈 여유) + 유지 시간
    final limit = _entered
        ? CompositionFit.exitScore
        : CompositionFit.enterScore;
    _entered = fit.hasEveryone && fit.score >= limit;
    if (_entered) {
      _matchedAt ??= now;
    } else {
      _matchedAt = null;
    }
    state = CompositionState(
      targets: targets,
      fit: _steady(fit, last?.fit, now),
      fits: _matchedAt != null && now.difference(_matchedAt!) >= holdDuration,
    );
  }

  /// 전면 카메라는 화면이 좌우반전이라 폰을 돌릴 방향이 반대.
  /// 행동 안내는 [actionDwell] 동안 유지해 문구가 깜빡이지 않게 한다.
  CompositionFit _steady(
    CompositionFit fit,
    CompositionFit? last,
    DateTime now,
  ) {
    var action = fit.action;
    if (ref.read(activeLensProvider) == CameraLensDirection.front) {
      action = switch (action) {
        CoachAction.panLeft => CoachAction.panRight,
        CoachAction.panRight => CoachAction.panLeft,
        _ => action,
      };
    }
    final urgent =
        action == CoachAction.hold ||
        action == CoachAction.findPerson ||
        last?.action == CoachAction.findPerson;
    var keep = fit;
    if (last != null &&
        action != last.action &&
        !urgent &&
        _actionAt != null &&
        now.difference(_actionAt!) < actionDwell) {
      action = last.action;
      keep = last;
    } else if (action != last?.action) {
      _actionAt = now;
    }
    return CompositionFit(
      targets: fit.targets,
      action: action,
      steps: keep.steps,
      who: keep.who,
    );
  }
}

/// 고스트(사진 프리셋의 반투명 사진)와 안내 패널을 잠깐 보여 줄지.
/// 구도를 고르거나 반전·투명도를 바꾸면 [duration] 동안 켜진다.
final ghostFlashProvider = NotifierProvider<GhostFlashNotifier, bool>(
  GhostFlashNotifier.new,
);

class GhostFlashNotifier extends Notifier<bool> {
  static const duration = Duration(seconds: 2);

  @override
  bool build() {
    ref
      ..watch(overlayOpacityProvider)
      ..watch(guideMirrorProvider);
    if (ref.watch(selectedPresetProvider) == null) return false;
    final timer = Timer(duration, () => state = false);
    ref.onDispose(timer.cancel);
    return true;
  }
}

/// 처음 위치를 잡을 때와 사람이 아직 없을 때만 true.
final ghostVisibleProvider = Provider<bool>((ref) {
  if (ref.watch(selectedPresetProvider) == null) return false;
  return ref.watch(ghostFlashProvider) ||
      !ref.watch(compositionProvider.select((s) => s?.hasPerson ?? false));
});
