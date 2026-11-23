import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/angle_state.dart';
import '../models/viewfinder_aspect.dart';
import '../services/telemetry_service.dart';
import 'api_providers.dart';
import 'attitude_providers.dart';
import 'preset_providers.dart';
import 'subject_providers.dart';

/// 촬영 신호. 셔터 링 색·진동·자동 촬영이 이 값 하나를 따른다.
/// 초록([ready])은 **사람의 크기·위치와 폰 각도가 모두 맞을 때만** 켜진다.
enum ShootSignal {
  /// 센서 대기·폰이 눕혀짐·사람이 아직 없음 (흰색)
  waiting,

  /// 사람이 목표 자리에 안 맞음 (노란색)
  adjusting,

  /// 사람은 맞고 폰 각도만 벗어남 (노란색)
  angleOff,

  /// 지금 찍으면 됨 (초록색)
  ready;

  static ShootSignal of(
    AngleState? angle, {
    required bool hasPerson,
    required bool fits,
  }) {
    if (angle == null || angle == AngleState.waiting || !hasPerson) {
      return waiting;
    }
    if (!fits) return adjusting;
    return angle == AngleState.good ? ready : angleOff;
  }
}

/// 프리셋이 없으면 null.
final shootSignalProvider =
    NotifierProvider.autoDispose<ShootSignalNotifier, ShootSignal?>(
      ShootSignalNotifier.new,
    );

class ShootSignalNotifier extends Notifier<ShootSignal?> {
  @override
  ShootSignal? build() {
    final preset = ref.watch(activePresetProvider);
    if (preset == null) return null;
    ref
      ..listen(angleGuideProvider, (_, _) => _refresh())
      ..listen(subjectProvider, (_, _) => _refresh());
    return _compute();
  }

  ShootSignal _compute() {
    final subject = ref.read(subjectProvider);
    return ShootSignal.of(
      ref.read(angleGuideProvider)?.state,
      hasPerson: subject?.hasPerson ?? false,
      fits: subject?.fits ?? false,
    );
  }

  void _refresh() {
    final before = state;
    final now = _compute();
    if (before == now) return;
    state = now;
    if (now != ShootSignal.ready) return;
    ref
        .read(telemetryProvider)
        ?.record(
          AppEvent.perfectMatch,
          preset: ref.read(selectedPresetProvider)?.id,
        );
    // 노랑 → 초록으로 바뀌는 순간에만 가벼운 진동 1회
    if (before == ShootSignal.angleOff || before == ShootSignal.adjusting) {
      HapticFeedback.lightImpact();
    }
  }
}

/// 가이드 잠금: 촬영자에게 폰을 넘길 때 오터치를 막는다.
final guideLockProvider = NotifierProvider<GuideLockNotifier, bool>(
  GuideLockNotifier.new,
);

class GuideLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void lock() {
    if (state || ref.read(selectedPresetProvider) == null) return;
    state = true;
    ref
        .read(telemetryProvider)
        ?.record(
          AppEvent.guideLocked,
          preset: ref.read(selectedPresetProvider)?.id,
        );
  }

  void unlock() => state = false;
}

/// 화면 비율 (저장 사진도 같은 비율).
final viewfinderAspectProvider =
    NotifierProvider<ViewfinderAspectNotifier, ViewfinderAspect>(
      ViewfinderAspectNotifier.new,
    );

class ViewfinderAspectNotifier extends Notifier<ViewfinderAspect> {
  @override
  ViewfinderAspect build() => ViewfinderAspect.r4x3;

  void cycle() => state = state.next;
}

/// 자동 촬영 켜기/끄기.
final autoShutterProvider = NotifierProvider<AutoShutterNotifier, bool>(
  AutoShutterNotifier.new,
);

class AutoShutterNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}
