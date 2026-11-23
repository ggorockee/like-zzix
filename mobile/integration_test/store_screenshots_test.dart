import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:likezzix/app.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/models/composition.dart';
import 'package:likezzix/models/composition_fit.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/providers/composition_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/providers/shooting_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/dynamic_frame.dart';
import 'package:likezzix/widgets/preset_bottom_sheet.dart';

/// App Store / Play 스크린샷. 시뮬레이터에는 카메라가 없어서 카메라 자리에
/// 선택한 프리셋의 레퍼런스 사진(생성형 AI)을 그리고, 자세·포즈 판정 값을 주입한다.
/// 실행 방법은 test_driver/screenshot_driver.dart 참고.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    final repository = PresetRepository();
    final presets = PresetRepository.merge(
      await repository.loadTemplates(),
      await repository.loadBundled(),
    );
    Preset of(String id) => presets.firstWhere((p) => p.id == id);

    // 자세: 기본은 선택한 프리셋 목표 각도와 일치. pitchOffset으로 어긋난 상태를 만든다.
    var pitchOffset = 0.0;
    var now = DateTime(2026, 11, 20, 9, 41);

    final container = ProviderContainer(
      overrides: [
        routerProvider.overrideWith((ref) {
          final router = GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const CameraScreen()),
            ],
          );
          ref.onDispose(router.dispose);
          return router;
        }),
        presetsProvider.overrideWith((ref) async => presets),
        availableCamerasProvider.overrideWith((ref) async => const []),
        visionClockProvider.overrideWithValue(() => now),
        attitudeProvider.overrideWith((ref) {
          final preset = ref.watch(selectedPresetProvider);
          return Stream.periodic(
            const Duration(milliseconds: 50),
            (_) =>
                Attitude(-(preset?.angle.elevationMid ?? 0) + pitchOffset, 0),
          );
        }),
        cameraBackdropProvider.overrideWithValue(const _DemoBackdrop()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const LikeZzixApp(),
      ),
    );
    await _settle(tester);

    Future<void> select(Preset preset) async {
      final notifier = container.read(selectedPresetProvider.notifier);
      if (container.read(selectedPresetProvider) != preset) {
        notifier.toggle(preset);
      }
      await _settle(tester);
    }

    /// 사람이 화면에 있는 상태를 만든다. [scale]은 목표 대비 크기, [shift]는 위치 차이.
    Future<void> person({double scale = 1, Offset shift = Offset.zero}) async {
      final finder = tester.getSize(find.byType(DynamicFrame));
      final targets = Target.of(container.read(activePresetProvider)!, finder);
      final people = [
        for (final t in targets)
          switch (t) {
            FaceTarget() => LivePerson.face(
              Rect.fromCenter(
                center: t.center + shift,
                width: t.box.width * scale,
                height: t.box.height * scale,
              ),
              yawDeg: switch (t.gaze) {
                Gaze.left => -25,
                Gaze.right => 25,
                null => 0,
              },
            ),
            BodyTarget() => LivePerson.body(
              BodyPoints({
                BodyAnchor.head: t.center + (t.head - t.center) * scale + shift,
                BodyAnchor.shoulders: t.center + shift,
                t.span: t.center + (t.bottom - t.center) * scale + shift,
              }, halfWidth: t.halfWidth * scale),
              t.span,
            ),
          },
      ];
      for (var i = 0; i < 15; i++) {
        now = now.add(const Duration(milliseconds: 100));
        container
            .read(compositionProvider.notifier)
            .update(people, targets, focal: finder.height);
      }
      await _settle(tester);
    }

    // 1. 좌우 대칭: 구도가 맞으면 가이드가 사라지고 초록 테두리
    await select(of('cmp-symmetry'));
    await person();
    await binding.takeScreenshot('01_perfect_match');

    // 2. 구도 목록 ([도식 | 예시] 카드)
    showPresetBottomSheet(tester.element(find.byType(CameraScreen)));
    await _settle(tester);
    await tester.tap(find.text(PresetCategory.travel.label));
    await _settle(tester);
    await binding.takeScreenshot('02_presets');
    Navigator.of(tester.element(find.byType(PresetBottomSheet))).pop();
    await _settle(tester);

    // 3. 삼분할: 사람은 구도에 맞았지만 폰 각도만 어긋난 상태
    pitchOffset = 9;
    await select(of('cmp-thirds'));
    await person();
    await binding.takeScreenshot('03_angle_guide');

    // 4. 오르는 대각선: 촬영자에게 넘긴 잠금 상태
    pitchOffset = 0;
    await select(of('cmp-ascending'));
    container.read(guideLockProvider.notifier).lock();
    await person(scale: 0.82);
    await binding.takeScreenshot('04_lock');
  });
}

/// 주기적인 자세 스트림 때문에 pumpAndSettle은 끝나지 않으므로 일정 시간만 진행.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 카메라 프리뷰 대신: 고른 구도의 예시 사진을 뷰파인더에 채운다.
class _DemoBackdrop extends ConsumerWidget {
  const _DemoBackdrop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider).value ?? const <Preset>[];
    final preset =
        ref.watch(selectedPresetProvider) ??
        (presets.isEmpty ? null : presets.first);
    final asset = preset?.referenceAsset;
    if (preset == null || asset == null) {
      return const ColoredBox(color: Colors.black);
    }
    // 예시 사진을 카메라 프리뷰처럼 뷰파인더에 채운다
    return SizedBox.expand(child: Image.asset(asset, fit: BoxFit.cover));
  }
}
