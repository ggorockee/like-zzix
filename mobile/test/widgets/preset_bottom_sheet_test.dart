import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/composition_card.dart';
import 'package:likezzix/widgets/native_ad_tile.dart';
import 'package:likezzix/widgets/preset_bottom_sheet.dart';

void main() {
  final presets = [
    ...PresetRepository.parseTemplates(
      File(PresetRepository.templatesAsset).readAsStringSync(),
    ),
    ...PresetRepository.parse(
      File(PresetRepository.bundledAsset).readAsStringSync(),
    ),
  ];
  List<Preset> of(PresetCategory c) => [
    for (final p in presets)
      if (p.category == c) p,
  ];

  Future<ProviderContainer> pumpSheet(WidgetTester tester) async {
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

  Finder card(String id) => find.byKey(ValueKey(id));

  testWidgets('4개 탭, 카드마다 [도식 | 예시], 광고 플래그 OFF면 광고 없음', (tester) async {
    await pumpSheet(tester);
    for (final c in PresetCategory.values) {
      expect(find.text(c.label), findsOneWidget);
    }
    final cards = find.byType(CompositionCard);
    expect(cards, findsWidgets);
    expect(
      find.descendant(
        of: cards.first,
        matching: find.byType(CompositionDiagram),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: cards.first,
        matching: find.byType(CompositionExample),
      ),
      findsOneWidget,
    );
    expect(find.byType(NativeAdTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('탭을 바꾸면 그 카테고리만', (tester) async {
    await pumpSheet(tester);
    for (final c in PresetCategory.values) {
      await tester.tap(find.text(c.label));
      await tester.pumpAndSettle();
      final shown = tester
          .widgetList<CompositionCard>(find.byType(CompositionCard))
          .map((w) => w.preset.id);
      expect(of(c).map((p) => p.id), containsAll(shown));
      expect(shown, isNotEmpty);
    }
  });

  testWidgets('고르면 선택되고 닫힘, 다시 열면 그 탭부터, 다시 고르면 해제', (tester) async {
    final container = await pumpSheet(tester);
    await tester.tap(find.text('특수/2인'));
    await tester.pumpAndSettle();
    await tester.tap(card('cmp-two-height'));
    await tester.pumpAndSettle();
    expect(container.read(selectedPresetProvider)?.id, 'cmp-two-height');
    expect(find.byType(PresetBottomSheet), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(card('cmp-two-height'), findsOneWidget);
    await tester.tap(card('cmp-two-height'));
    await tester.pumpAndSettle();
    expect(container.read(selectedPresetProvider), isNull);
  });

  testWidgets('큰 글자에서도 카드가 넘치지 않음', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpSheet(tester);
    expect(tester.takeException(), isNull);
  });
}
