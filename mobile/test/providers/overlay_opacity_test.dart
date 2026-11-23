import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final template = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  ).first;
  final photo = PresetRepository.parse(
    File(PresetRepository.bundledAsset).readAsStringSync(),
  ).last; // 구도와 id가 다른 사진

  Future<ProviderContainer> open() async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.listen(overlayOpacityProvider, (_, _) {});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return c;
  }

  test('기본은 실루엣 아주 흐리게(12%), 사진 40%', () async {
    SharedPreferences.setMockInitialValues({});
    final c = await open();
    c.read(selectedPresetProvider.notifier).toggle(template);
    expect(c.read(overlayOpacityProvider), 0.12);
    c.read(selectedPresetProvider.notifier).toggle(photo);
    expect(c.read(overlayOpacityProvider), 0.4);
  });

  test('0~1로 조절하고, 바꾼 값은 앱을 다시 켜도 유지된다', () async {
    SharedPreferences.setMockInitialValues({});
    final first = await open();
    first.read(selectedPresetProvider.notifier).toggle(template);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final notifier = first.read(overlayOpacityProvider.notifier);
    notifier.set(-1);
    expect(first.read(overlayOpacityProvider), 0); // 완전히 숨기기
    notifier.set(0.33);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final second = await open();
    second.read(selectedPresetProvider.notifier).toggle(template);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(second.read(overlayOpacityProvider), 0.33);
  });
}
