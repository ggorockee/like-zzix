import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart' show CameraLensDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/subject.dart';
import 'camera_providers.dart';
import 'preset_providers.dart';

/// 화면 속 인물과 목표 구도의 현재 상태.
@immutable
class SubjectState {
  const SubjectState({
    required this.target,
    required this.fit,
    this.live,
    this.fits = false,
  });

  final SubjectTarget target;
  final SubjectFit fit;

  /// 떨림을 줄인 현재 인물. 안 보이면 null.
  final Subject? live;

  /// 구도 일치 (90점 이상 진입, 86점 미만 이탈, [SubjectNotifier.holdDuration] 유지)
  final bool fits;

  bool get hasPerson => live != null;
}

/// 현재 시각 (테스트에서 교체).
final subjectClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 인물 추적. 카메라 화면이 포즈 프레임마다 [SubjectNotifier.update]를 부른다.
final subjectProvider = NotifierProvider<SubjectNotifier, SubjectState?>(
  SubjectNotifier.new,
);

class SubjectNotifier extends Notifier<SubjectState?> {
  /// 일치로 인정하기까지 유지해야 하는 시간
  static const holdDuration = Duration(milliseconds: 250);

  /// 인식이 잠깐 끊겨도 사람이 있는 것으로 보는 시간
  static const lostGrace = Duration(milliseconds: 500);

  /// 안내 문구가 너무 빨리 바뀌지 않게 하는 최소 유지 시간
  static const actionDwell = Duration(milliseconds: 450);

  static const _smoothTau = 0.12; // 초

  Subject? _live;
  DateTime? _seenAt;
  DateTime? _updatedAt;
  DateTime? _matchedAt;
  DateTime? _actionAt;
  bool _entered = false;

  @override
  SubjectState? build() {
    ref.watch(activePresetProvider);
    _reset();
    return null;
  }

  void _reset() {
    _live = null;
    _seenAt = _updatedAt = _matchedAt = _actionAt = null;
    _entered = false;
  }

  void clear() {
    _reset();
    state = null;
  }

  /// [found]는 이번 프레임의 인물(없으면 null), [focal]은 화면 단위 초점거리.
  void update(Subject? found, SubjectTarget target, {required double focal}) {
    final now = ref.read(subjectClockProvider)();
    final dt = _updatedAt == null
        ? 0.0
        : now.difference(_updatedAt!).inMicroseconds / 1e6;
    _updatedAt = now;
    if (found != null) {
      _seenAt = now;
      _live = _live == null
          ? found
          : _live!.lerpTo(found, 1 - math.exp(-dt / _smoothTau));
    } else if (_seenAt == null || now.difference(_seenAt!) > lostGrace) {
      _live = null;
    }

    final last = state;
    // 화면 비율이 바뀌었으면 이전 판정을 쓰지 않는다
    final sameTarget = last?.target.finder == target.finder;
    var fit = SubjectFit.evaluate(
      _live,
      target,
      focal: focal,
      previousHits: sameTarget ? last!.fit.hits : const {},
    );

    // 히스테리시스 + 유지 시간
    final limit = _entered ? SubjectFit.exitScore : SubjectFit.enterScore;
    _entered = _live != null && fit.score >= limit;
    if (_entered) {
      _matchedAt ??= now;
    } else {
      _matchedAt = null;
    }
    final fits =
        _matchedAt != null && now.difference(_matchedAt!) >= holdDuration;

    state = SubjectState(
      target: target,
      live: _live,
      fits: fits,
      fit: _steady(fit, last?.fit, now),
    );
  }

  /// 전면 카메라는 화면이 좌우반전이라 폰을 돌릴 방향이 반대.
  /// 행동 안내는 [actionDwell] 동안 유지해 문구가 깜빡이지 않게 한다.
  SubjectFit _steady(SubjectFit fit, SubjectFit? last, DateTime now) {
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
    if (last != null &&
        action != last.action &&
        !urgent &&
        _actionAt != null &&
        now.difference(_actionAt!) < actionDwell) {
      action = last.action;
    } else if (action != last?.action) {
      _actionAt = now;
    }
    return SubjectFit(
      action: action,
      score: fit.score,
      scale: fit.scale,
      steps: fit.steps,
      hits: fit.hits,
    );
  }
}

/// 고스트(반투명 실루엣·사진)를 잠깐 다시 보여 줄지.
/// 프리셋을 고르거나 반전·투명도를 바꾸면 [duration] 동안 켜진다.
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

/// 고스트 표시 여부: 처음 위치를 잡을 때와 사람이 아직 없을 때만.
final ghostVisibleProvider = Provider<bool>((ref) {
  if (ref.watch(selectedPresetProvider) == null) return false;
  return ref.watch(ghostFlashProvider) ||
      !ref.watch(subjectProvider.select((s) => s?.hasPerson ?? false));
});
