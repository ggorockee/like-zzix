import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/native_ad_tile.dart';
import 'package:likezzix/widgets/preset_bottom_sheet.dart';
import 'package:likezzix/widgets/preset_grid_item.dart';

void main() {
  final presets = PresetRepository.parse(
    File(PresetRepository.bundledAsset).readAsStringSync(),
  );

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
    // 실제 폰과 비슷한 화면 크기 (360x800 논리 픽셀)
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [presetsProvider.overrideWith((ref) async => presets)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPresetBottomSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('광고 플래그 OFF: 5번째 칸도 기본 프리셋으로 채움', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(NativeAdTile), findsNothing);
    expect(find.byType(CreateFromPhotoItem), findsOneWidget);
    // 첫 칸(내 사진) 다음부터 순서대로 → 5번째 칸 = presets[3]
    final items = tester
        .widgetList<PresetGridItem>(find.byType(PresetGridItem))
        .toList();
    expect(items[3].preset, presets[3]);
  });

  testWidgets('카테고리 필터', (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, '상반신'));
    await tester.pumpAndSettle();

    final shown = tester
        .widgetList<PresetGridItem>(find.byType(PresetGridItem))
        .map((w) => w.preset.title);
    expect(shown, ['턱 괴기', '손 인사']);
  });

  testWidgets('프리셋을 고르면 선택되고 시트가 닫힘, 다시 고르면 해제', (tester) async {
    final container = await pumpSheet(tester);
    await tester.tap(find.text(presets.first.title));
    await tester.pumpAndSettle();

    expect(container.read(selectedPresetProvider), presets.first);
    expect(find.byType(PresetBottomSheet), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(presets.first.title));
    await tester.pumpAndSettle();
    expect(container.read(selectedPresetProvider), isNull);
  });
}
