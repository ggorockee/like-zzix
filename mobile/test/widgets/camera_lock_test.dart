import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/providers/shooting_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/lock_button.dart';
import 'package:likezzix/widgets/shutter_button.dart';

void main() {
  final templates = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );

  Future<ProviderContainer> pumpCamera(
    WidgetTester tester, {
    Stream<Attitude>? attitude,
    Size size = const Size(360, 880),
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        presetsProvider.overrideWith((ref) async => templates),
        availableCamerasProvider.overrideWith((ref) async => const []),
        attitudeProvider.overrideWith(
          (ref) => attitude ?? Stream.value(const Attitude(0, 0)),
        ),
        cameraBackdropProvider.overrideWithValue(const SizedBox.expand()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: CameraScreen()),
      ),
    );
    container
        .read(selectedPresetProvider.notifier)
        .toggle(templates.firstWhere((t) => t.id == 'cmp-full-body'));
    await tester.pump();
    // 고스트 표시 시간(2초)이 끝난 상태
    await tester.pump(const Duration(milliseconds: 2100));
    return container;
  }

  testWidgets('한 번 탭으로 잠그면 셔터·배율·잠금 해제만 남는다', (tester) async {
    final container = await pumpCamera(tester);
    expect(find.bySemanticsLabel('화면 비율'), findsOneWidget);
    expect(find.byTooltip('구도 프리셋'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('가이드 잠금'));
    await tester.pump();

    expect(container.read(guideLockProvider), isTrue);
    for (final label in ['화면 비율', '가이드 좌우 반전', '자동 촬영']) {
      expect(find.bySemanticsLabel(label), findsNothing, reason: label);
    }
    for (final tip in ['구도 프리셋', '갤러리', '렌즈 전환']) {
      expect(find.byTooltip(tip), findsNothing, reason: tip);
    }
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(ShutterButton), findsOneWidget);
    expect(find.text('0.5'), findsOneWidget);
    expect(find.text('3'), findsNothing); // 잠금 중에는 2배까지
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);
  });

  testWidgets('잠금 해제는 길게 눌러야 한다', (tester) async {
    final container = await pumpCamera(tester);
    await tester.tap(find.bySemanticsLabel('가이드 잠금'));
    await tester.pump();

    // 짧게 누르면 그대로
    await tester.tap(find.byType(LockButton));
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(guideLockProvider), isTrue);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LockButton)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(guideLockProvider), isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(container.read(guideLockProvider), isFalse);
    await gesture.up();
    await tester.pump();
    expect(find.bySemanticsLabel('화면 비율'), findsOneWidget);
  });

  testWidgets('사람이 없으면 각도가 맞아도 셔터 링이 초록이 아니다', (tester) async {
    // 전신 구도 권장 각도(위로 5~10°) 안
    final container = await pumpCamera(
      tester,
      attitude: Stream.value(const Attitude(-7, 0)),
    );
    expect(container.read(shootSignalProvider), ShootSignal.waiting);
    expect(
      tester.widget<ShutterButton>(find.byType(ShutterButton)).ready,
      isFalse,
    );
    expect(find.text('찍을 사람을 화면에 비추세요'), findsOneWidget);
  });

  testWidgets('작은 화면·큰 글자에서도 넘치지 않음', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.35;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await pumpCamera(tester, size: const Size(360, 640));
    for (var i = 0; i < 3; i++) {
      container.read(viewfinderAspectProvider.notifier).cycle();
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
