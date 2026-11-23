import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:likezzix/app.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/models/guide_motion.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/providers/guide_motion_provider.dart';
import 'package:likezzix/providers/pose_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/preset_bottom_sheet.dart';
import 'package:likezzix/widgets/silhouette_painter.dart';

/// App Store / Play 스크린샷. 시뮬레이터에는 카메라가 없어서 카메라 자리에
/// 선택한 프리셋의 레퍼런스 사진(생성형 AI)을 그리고, 자세·포즈 판정 값을 주입한다.
/// 실행 방법은 test_driver/screenshot_driver.dart 참고.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    final presets = await PresetRepository().loadBundled();
    final fullBody = presets.firstWhere((p) => p.id == 'full-body-low-angle');
    final cafe = presets.firstWhere((p) => p.id == 'drink-cafe');

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
        poseClockProvider.overrideWithValue(() => now),
        attitudeProvider.overrideWith((ref) {
          final preset = ref.watch(selectedPresetProvider);
          return Stream.periodic(
            const Duration(milliseconds: 50),
            (_) => Attitude((preset?.pitchDeg ?? 0) + pitchOffset, 0),
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

    /// 레퍼런스 관절을 실시간 관절로 넣어 구도 일치(Perfect Match) 상태를 만든다.
    Future<void> perfect() async {
      final live = container.read(selectedPresetProvider)!.landmarks;
      final pose = container.read(poseMatchProvider.notifier);
      pose.update(live);
      now = now.add(const Duration(seconds: 1));
      pose.update(live);
      await _settle(tester);
    }

    // 1. 전신샷: 실루엣에 맞추면 "지금 찍으세요"
    pitchOffset = 0;
    await select(fullBody);
    await perfect();
    await binding.takeScreenshot('01_perfect_match');

    // 2. 구도 프리셋 목록
    showPresetBottomSheet(tester.element(find.byType(CameraScreen)));
    await _settle(tester);
    await binding.takeScreenshot('02_presets');
    Navigator.of(tester.element(find.byType(PresetBottomSheet))).pop();
    await _settle(tester);

    // 3. 음료 컷: 각도가 어긋나면 어느 쪽으로 얼마나 기울일지 안내
    pitchOffset = 9;
    await select(cafe);
    // 사람은 구도에 맞았지만 폰 각도만 어긋난 상태
    final screen = tester.getSize(find.byType(CameraScreen));
    final person = container
        .read(guideMotionProvider)
        .displace(
          cafe.landmarks,
          screen: screen,
          frame: SilhouettePainter.frameRect(screen, cafe.aspectRatio),
          focal: GuideMotion.focalLength(screen.height, 1),
        );
    container
        .read(poseMatchProvider.notifier)
        .update(person, reference: person);
    await _settle(tester);
    await binding.takeScreenshot('03_angle_guide');
  });
}

/// 주기적인 자세 스트림 때문에 pumpAndSettle은 끝나지 않으므로 일정 시간만 진행.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 카메라 프리뷰 대신: 프리셋 사진을 가이드 프레임 위치에 그리고, 나머지는 같은 사진을 흐리게 채운다.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final frame = SilhouettePainter.frameRect(
          constraints.biggest,
          preset.aspectRatio,
        );
        return Stack(
          children: [
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Image.asset(asset, fit: BoxFit.cover),
              ),
            ),
            // 실제 카메라처럼 폰 각도에 따라 장면도 움직인다
            Positioned.fill(
              child: Transform(
                transform: ref
                    .watch(guideMotionProvider)
                    .matrix(
                      constraints.biggest,
                      GuideMotion.focalLength(constraints.maxHeight, 1),
                    ),
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: frame,
                      child: Image.asset(asset, fit: BoxFit.fill),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
