import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/angle_state.dart';
import 'package:likezzix/models/composition_fit.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/providers/composition_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/providers/shooting_providers.dart';
import 'package:likezzix/services/preset_repository.dart';

class _FakeAngle extends AngleGuideNotifier {
  _FakeAngle(this.angle);

  final AngleState angle;

  void set(AngleState s) =>
      state = AngleGuide(state: s, pitchDelta: 0, rollDelta: 0);

  @override
  AngleGuide? build() =>
      AngleGuide(state: angle, pitchDelta: 0, rollDelta: 0, pitchError: 5);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const finder = Size(360, 480);
  final presets = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );
  final preset = presets.firstWhere((p) => p.id == 'cmp-thirds');
  final targets = Target.of(preset, finder);
  final radius = (targets.single as FaceTarget).radius;
  late DateTime now;
  final haptics = <Object?>[];

  LivePerson person([Offset shift = Offset.zero]) =>
      LivePerson.face(targets.single.box.shift(shift));

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
        visionClockProvider.overrideWithValue(() => now),
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
    List<LivePerson> people, {
    int count = 8,
  }) async {
    for (var i = 0; i < count; i++) {
      now = now.add(const Duration(milliseconds: 80));
      c.read(compositionProvider.notifier).update(people, targets, focal: 480);
      await c.pump();
    }
  }

  ShootSignal? signal(ProviderContainer c) => c.read(shootSignalProvider);

  test('각도가 맞아도 사람이 없으면 초록불이 켜지지 않는다', () async {
    final c = await container(AngleState.good);
    await frames(c, const []);
    expect(signal(c), ShootSignal.waiting);
    expect(haptics, isEmpty);
  });

  test('사람이 맞아도 각도가 벗어나면 초록불이 아니다', () async {
    final c = await container(AngleState.off);
    await frames(c, [person()]);
    expect(signal(c), ShootSignal.angleOff);
  });

  test('사람과 각도가 모두 맞고 유지되면 초록불 + 가벼운 진동 1회', () async {
    final c = await container(AngleState.good);
    await frames(c, [person()], count: 2);
    expect(signal(c), ShootSignal.adjusting);
    await frames(c, [person()]);
    expect(signal(c), ShootSignal.ready);
    await frames(c, [person()], count: 20);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  test('경계에서 흔들려도 초록불이 깜빡이지 않는다 (진입 엄격 / 이탈 여유)', () async {
    final c = await container(AngleState.good);
    await frames(c, [person()]);
    var changes = 0;
    c.listen(shootSignalProvider, (_, _) => changes++);
    for (var i = 0; i < 30; i++) {
      await frames(c, [
        person(Offset(radius * (i.isEven ? 1.25 : 0.85), 0)),
      ], count: 1);
    }
    expect(signal(c), ShootSignal.ready);
    expect(changes, 0);
    // 여유를 넘으면 해제
    await frames(c, [person(Offset(radius * 1.8, 0))], count: 15);
    expect(signal(c), ShootSignal.adjusting);
  });

  test('인식이 잠깐 끊기는 것은 무시하고, 오래 끊기면 사람 없음', () async {
    final c = await container(AngleState.good);
    await frames(c, [person()]);
    await frames(c, const [], count: 4);
    expect(signal(c), ShootSignal.ready);
    await frames(c, const [], count: 6);
    expect(signal(c), ShootSignal.waiting);
  });

  test('폰을 옮길 방향은 전면 카메라에서도 화면 방향 그대로', () async {
    final c = await container(AngleState.good);
    await frames(c, [person(const Offset(70, 0))]);
    expect(c.read(compositionProvider)!.fit.action, CoachAction.moveRight);
    c.read(activeLensProvider.notifier).set(CameraLensDirection.front);
    await frames(c, [person(const Offset(70, 0))]);
    expect(c.read(compositionProvider)!.fit.action, CoachAction.moveRight);
  });

  group('촬영 중 인식이 멈추면', () {
    test('남은 판정으로 초록불이 켜지지 않고, 새 프레임으로 다시 판정한다', () async {
      final c = await container(AngleState.off);
      await frames(c, [person()]);
      expect(signal(c), ShootSignal.angleOff);

      // 촬영 시작 → 사람은 화면에서 벗어나고 폰 각도만 맞음
      c.read(compositionProvider.notifier).pause();
      (c.read(angleGuideProvider.notifier) as _FakeAngle).set(AngleState.good);
      await c.pump();
      expect(signal(c), ShootSignal.paused);

      now = now.add(const Duration(seconds: 4));
      await frames(c, const [], count: 1);
      expect(signal(c), ShootSignal.waiting);
      expect(haptics, isEmpty);
    });

    test('그대로 서 있으면 초록불이 이어지고 진동은 다시 울리지 않는다', () async {
      final c = await container(AngleState.good);
      await frames(c, [person()]);
      expect(haptics, hasLength(1));
      c.read(compositionProvider.notifier).pause();
      await c.pump();
      expect(signal(c), ShootSignal.paused);
      now = now.add(const Duration(seconds: 4));
      await frames(c, [person()], count: 1);
      expect(signal(c), ShootSignal.ready);
      expect(haptics, hasLength(1));
    });

    test('구도가 없으면 아무 일도 없다', () async {
      final c = await container(AngleState.good);
      c.read(compositionProvider.notifier).pause();
      expect(c.read(compositionProvider), isNull);
    });
  });

  test('고스트·안내 패널: 고른 직후와 사람이 없을 때만', () async {
    final c = await container(AngleState.good);
    c.listen(ghostVisibleProvider, (_, _) {});
    expect(c.read(ghostVisibleProvider), isTrue);
    await Future<void>.delayed(
      GhostFlashNotifier.duration + const Duration(milliseconds: 50),
    );
    await frames(c, [person()]);
    expect(c.read(ghostVisibleProvider), isFalse);
    await frames(c, const [], count: 10);
    expect(c.read(ghostVisibleProvider), isTrue);
  });

  test('구도를 해제하면 신호 없음', () async {
    final c = await container(AngleState.good);
    await frames(c, [person()]);
    c.read(selectedPresetProvider.notifier).clear();
    await c.pump();
    expect(signal(c), isNull);
    expect(c.read(compositionProvider), isNull);
  });
}
