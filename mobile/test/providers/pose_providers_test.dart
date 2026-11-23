import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/models/preset.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/pose_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';

/// 센서 없이 각도 일치 여부를 고정
class _FixedAngle extends AngleGuideNotifier {
  _FixedAngle(this.matched);

  final bool matched;

  @override
  AngleGuide? build() => AngleGuide(
    pitchDelta: 0,
    rollDelta: 0,
    matched: matched,
    tilt: TiltHint.none,
    level: LevelHint.none,
  );
}

Preset _preset(List<PoseLandmark> landmarks) => Preset(
  id: 'p',
  category: PresetCategory.fullBody,
  title: 't',
  tip: '',
  aspectRatio: 1,
  pitchDeg: 0,
  rollDeg: 0,
  landmarks: landmarks,
  sortOrder: 0,
);

List<PoseLandmark> _body([double dx = 0]) => [
  for (var i = 0; i < PoseIndex.count; i++)
    PoseLandmark(0.3 + (i % 5) * 0.1 + dx, 0.1 + (i ~/ 5) * 0.12, 0.95),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime now;
  final haptics = <Object?>[];

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

  ProviderContainer container({required bool angleOk}) {
    now = DateTime(2026, 11, 18, 12);
    final c = ProviderContainer(
      overrides: [
        angleGuideProvider.overrideWith(() => _FixedAngle(angleOk)),
        poseClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    c.listen(angleGuideProvider, (_, _) {});
    c.read(selectedPresetProvider.notifier).toggle(_preset(_body()));
    return c;
  }

  test('포즈·각도 일치가 300ms 유지돼야 Perfect', () {
    final c = container(angleOk: true);
    final notifier = c.read(poseMatchProvider.notifier);

    notifier.update(_body());
    expect(c.read(poseMatchProvider)!.result.matched, isTrue);
    expect(c.read(poseMatchProvider)!.perfect, isFalse);

    now = now.add(const Duration(milliseconds: 200));
    notifier.update(_body());
    expect(c.read(poseMatchProvider)!.perfect, isFalse);

    now = now.add(const Duration(milliseconds: 150));
    notifier.update(_body());
    expect(c.read(poseMatchProvider)!.perfect, isTrue);

    // 진입 순간 1회만 진동
    now = now.add(const Duration(milliseconds: 100));
    notifier.update(_body());
    expect(haptics, ['HapticFeedbackType.heavyImpact']);
  });

  test('중간에 어긋나면 유지 시간 초기화', () {
    final c = container(angleOk: true);
    final notifier = c.read(poseMatchProvider.notifier);
    notifier.update(_body());
    now = now.add(const Duration(milliseconds: 250));
    notifier.update(_body(0.3)); // 크게 어긋남
    now = now.add(const Duration(milliseconds: 100));
    notifier.update(_body());
    expect(c.read(poseMatchProvider)!.perfect, isFalse);
  });

  test('각도가 안 맞으면 포즈가 맞아도 Perfect 아님', () {
    final c = container(angleOk: false);
    final notifier = c.read(poseMatchProvider.notifier);
    notifier.update(_body());
    now = now.add(const Duration(seconds: 1));
    notifier.update(_body());
    expect(c.read(poseMatchProvider)!.result.matched, isTrue);
    expect(c.read(poseMatchProvider)!.perfect, isFalse);
  });

  test('움직인 가이드에 사람이 맞아도 각도가 안 맞으면 Perfect 아님', () {
    final c = container(angleOk: false);
    final notifier = c.read(poseMatchProvider.notifier);
    // 가이드와 사람이 함께 0.3만큼 밀린 상태: 위치 안내는 나오지 않아야 한다
    notifier.update(_body(0.3), reference: _body(0.3));
    now = now.add(const Duration(seconds: 1));
    notifier.update(_body(0.3), reference: _body(0.3));
    final state = c.read(poseMatchProvider)!;
    expect(state.result.matched, isTrue);
    expect(state.perfect, isFalse);
  });

  test('프리셋을 바꾸면 판정 초기화', () {
    final c = container(angleOk: true);
    c.read(poseMatchProvider.notifier).update(_body());
    expect(c.read(poseMatchProvider), isNotNull);
    c.read(selectedPresetProvider.notifier).clear();
    expect(c.read(poseMatchProvider), isNull);
  });
}
