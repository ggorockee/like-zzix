import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/angle_state.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/providers/shooting_providers.dart';
import 'package:likezzix/providers/subject_providers.dart';
import 'package:likezzix/services/preset_repository.dart';

/// 센서 없이 각도 상태를 고정·변경
class _FakeAngle extends AngleGuideNotifier {
  _FakeAngle(this.initial);

  final AngleState initial;

  static AngleGuide guide(AngleState s) =>
      AngleGuide(state: s, pitchDelta: 0, rollDelta: 0, pitchError: 5);

  @override
  AngleGuide? build() => guide(initial);

  void set(AngleState s) => state = guide(s);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const finder = Size(360, 480);
  final preset = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  ).first;
  final target = SubjectTarget.of(preset, finder)!;
  late DateTime now;
  final haptics = <Object?>[];

  Subject person([double dx = 0]) => Subject({
    for (final e in target.subject.points.entries)
      e.key: e.value + Offset(dx, 0),
  }, halfWidth: 40);

  setUp(() {
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments);
          }
          return null;
        });
  });

  Future<ProviderContainer> container(AngleState angle) async {
    now = DateTime(2026, 11, 23, 12);
    final c = ProviderContainer(
      overrides: [
        angleGuideProvider.overrideWith(() => _FakeAngle(angle)),
        subjectClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    c.read(selectedPresetProvider.notifier).toggle(preset);
    c
      ..listen(angleGuideProvider, (_, _) {})
      ..listen(shootSignalProvider, (_, _) {});
    await c.pump();
    return c;
  }

  Future<void> frames(
    ProviderContainer c,
    Subject? s, {
    int count = 8,
    int ms = 80,
  }) async {
    for (var i = 0; i < count; i++) {
      now = now.add(Duration(milliseconds: ms));
      c.read(subjectProvider.notifier).update(s, target, focal: 480);
      await c.pump();
    }
  }

  ShootSignal? signal(ProviderContainer c) => c.read(shootSignalProvider);

  test('각도가 맞아도 사람이 없으면 초록불이 켜지지 않는다', () async {
    final c = await container(AngleState.good);
    await frames(c, null);
    expect(signal(c), ShootSignal.waiting);
    expect(haptics, isEmpty);
  });

  test('사람이 맞아도 각도가 벗어나면 초록불이 아니다', () async {
    final c = await container(AngleState.off);
    await frames(c, person());
    expect(signal(c), ShootSignal.angleOff);
  });

  test('사람과 각도가 모두 맞고 유지되면 초록불 + 가벼운 진동 1회', () async {
    final c = await container(AngleState.good);
    await frames(c, person(), count: 2);
    expect(signal(c), ShootSignal.adjusting); // 아직 유지 시간 전
    await frames(c, person());
    expect(signal(c), ShootSignal.ready);
    await frames(c, person(), count: 20);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  test('사람 경계에서 흔들려도 초록불이 깜빡이지 않는다', () async {
    final c = await container(AngleState.good);
    await frames(c, person());
    var changes = 0;
    c.listen(shootSignalProvider, (_, _) => changes++);
    // 허용 오차(약 19px) 경계를 오가는 흔들림
    for (var i = 0; i < 30; i++) {
      await frames(c, person(i.isEven ? 23 : 16), count: 1);
    }
    expect(signal(c), ShootSignal.ready);
    expect(changes, 0);
  });

  test('인식이 잠깐 끊기는 것은 무시하고, 오래 끊기면 사람 없음', () async {
    final c = await container(AngleState.good);
    await frames(c, person());
    await frames(c, null, count: 4); // 0.32초
    expect(signal(c), ShootSignal.ready);
    await frames(c, null, count: 6);
    expect(signal(c), ShootSignal.waiting);
  });

  test('전면 카메라는 좌우 안내가 반대', () async {
    final c = await container(AngleState.good);
    await frames(c, person(90));
    expect(c.read(subjectProvider)!.fit.action, CoachAction.panRight);
    c.read(activeLensProvider.notifier).set(CameraLensDirection.front);
    await frames(c, person(90));
    expect(c.read(subjectProvider)!.fit.action, CoachAction.panLeft);
  });

  test('고스트: 고른 직후와 사람이 없을 때만 보인다', () async {
    final c = await container(AngleState.good);
    c.listen(ghostVisibleProvider, (_, _) {});
    expect(c.read(ghostVisibleProvider), isTrue); // 고른 직후
    await frames(c, person());
    expect(c.read(ghostVisibleProvider), isTrue); // 2초 동안은 유지
    await Future<void>.delayed(
      GhostFlashNotifier.duration + const Duration(milliseconds: 50),
    );
    await c.pump();
    expect(c.read(ghostVisibleProvider), isFalse);
    await frames(c, null, count: 10);
    expect(c.read(ghostVisibleProvider), isTrue); // 사람이 사라짐
  });

  test('프리셋을 해제하면 신호 없음', () async {
    final c = await container(AngleState.good);
    await frames(c, person());
    c.read(selectedPresetProvider.notifier).clear();
    await c.pump();
    expect(signal(c), isNull);
    expect(c.read(subjectProvider), isNull);
  });
}
