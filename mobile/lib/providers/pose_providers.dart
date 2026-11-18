import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pose_match.dart';
import '../models/preset.dart';
import '../services/telemetry_service.dart';
import 'api_providers.dart';
import 'attitude_providers.dart';
import 'preset_providers.dart';

/// 실시간 구도 판정 상태.
@immutable
class PoseMatchState {
  const PoseMatchState({
    required this.result,
    required this.live,
    required this.perfect,
  });

  final PoseMatchResult result;

  /// 프레임 정규화 좌표의 실시간 관절 (사람이 없으면 null)
  final List<PoseLandmark>? live;

  /// 포즈 + 각도가 함께 일치한 상태가 [PoseMatchNotifier.holdDuration] 이상 유지됨
  final bool perfect;
}

/// 현재 시각 (테스트에서 교체).
final poseClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// 선택한 프리셋 대비 실시간 포즈 판정. 프리셋이 없으면 null.
final poseMatchProvider = NotifierProvider<PoseMatchNotifier, PoseMatchState?>(
  PoseMatchNotifier.new,
);

class PoseMatchNotifier extends Notifier<PoseMatchState?> {
  /// Perfect Match로 인정하기까지 유지해야 하는 시간 (깜빡임 방지)
  static const holdDuration = Duration(milliseconds: 300);

  final _matcher = PoseMatcher();
  DateTime? _since;

  @override
  PoseMatchState? build() {
    ref.watch(selectedPresetProvider);
    _matcher.reset();
    _since = null;
    return null;
  }

  /// 카메라 화면이 프레임마다 호출. [live]는 프레임 정규화 좌표.
  void update(List<PoseLandmark>? live) {
    final preset = ref.read(selectedPresetProvider);
    if (preset == null) {
      state = null;
      return;
    }
    final result = _matcher.evaluate(
      preset.landmarks,
      live,
      aspectRatio: preset.aspectRatio,
    );
    final angleOk = ref.read(angleGuideProvider)?.matched ?? false;
    final now = ref.read(poseClockProvider)();
    final wasPerfect = state?.perfect ?? false;

    var perfect = false;
    if (result.matched && angleOk) {
      _since ??= now;
      perfect = now.difference(_since!) >= holdDuration;
    } else {
      _since = null;
    }
    if (perfect && !wasPerfect) {
      // "지금 찍으세요!" 진입 시 1회 (PRD: 0.1초 진동)
      HapticFeedback.heavyImpact();
      ref
          .read(telemetryProvider)
          ?.record(AppEvent.perfectMatch, preset: preset.id);
    }
    state = PoseMatchState(result: result, live: live, perfect: perfect);
  }

  void clear() {
    _matcher.reset();
    _since = null;
    state = null;
  }
}
