import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/ad_flags.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/models/composition_fit.dart';
import 'package:likezzix/models/subject.dart';
import 'package:likezzix/providers/ad_providers.dart';
import 'package:likezzix/providers/attitude_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/providers/composition_providers.dart';
import 'package:likezzix/providers/preset_providers.dart';
import 'package:likezzix/providers/shooting_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';
import 'package:likezzix/services/capture_service.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/widgets/capture_notice.dart';
import 'package:likezzix/widgets/coach_pill.dart';
import 'package:likezzix/widgets/shutter_button.dart';
import 'package:likezzix/widgets/zoom_selector.dart';

/// 촬영이 끝나는 시점을 테스트가 정하는 카메라.
class _FakeCamera extends CameraPlatform {
  Completer<XFile> picture = Completer();
  int pictures = 0;
  int streamStarts = 0;
  int streaming = 0;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings? mediaSettings,
  ) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1280,
          960,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;

  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 3;

  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    streamStarts++;
    late final StreamController<CameraImageData> frames;
    frames = StreamController(
      onListen: () => streaming++,
      onCancel: () => streaming--,
    );
    return frames.stream;
  }

  @override
  Future<XFile> takePicture(int cameraId) {
    pictures++;
    return picture.future;
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<void> dispose(int cameraId) async {}
}

class _FakeCapture extends CaptureService {
  Completer<SaveResult> saved = Completer();

  @override
  Future<SaveResult> saveToGallery(String path) => saved.future;
}

void main() {
  final templates = PresetRepository.parseTemplates(
    File(PresetRepository.templatesAsset).readAsStringSync(),
  );
  const good = Attitude(0, 0);

  // 카메라가 아래를 봄: 권장 범위 밖
  const tiltedDown = Attitude(12, 0);

  late _FakeCamera camera;
  late _FakeCapture capture;
  late StreamController<Attitude> attitude;
  late ProviderContainer container;
  late DateTime now;

  Future<void> pumpCamera(WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    camera = _FakeCamera();
    CameraPlatform.instance = camera;
    capture = _FakeCapture();
    attitude = StreamController.broadcast();
    addTearDown(attitude.close);
    now = DateTime(2026, 11, 25, 22);
    container = ProviderContainer(
      overrides: [
        presetsProvider.overrideWith((ref) async => templates),
        availableCamerasProvider.overrideWith(
          (ref) async => const [
            CameraDescription(
              name: 'back',
              lensDirection: CameraLensDirection.back,
              sensorOrientation: 90,
            ),
          ],
        ),
        attitudeProvider.overrideWith((ref) => attitude.stream),
        captureServiceProvider.overrideWithValue(capture),
        adFlagsProvider.overrideWithValue(AdFlags.defaults),
        visionClockProvider.overrideWithValue(() => now),
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
        .toggle(templates.firstWhere((t) => t.id == 'cmp-thirds'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 600));
    }
  }

  List<Target> targets() =>
      Target.of(container.read(activePresetProvider)!, const Size(360, 480));

  /// 인식 프레임 [count]장을 흉내 낸다.
  Future<void> frames(
    WidgetTester tester, {
    required bool inPlace,
    int count = 8,
  }) async {
    for (var i = 0; i < count; i++) {
      now = now.add(const Duration(milliseconds: 80));
      final t = targets();
      container
          .read(compositionProvider.notifier)
          .update([if (inPlace) LivePerson.face(t.single.box)], t, focal: 480);
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  /// 사진 자르기(isolate)처럼 실제 시간이 걸리는 일을 기다린다.
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  ShootSignal? signal() => container.read(shootSignalProvider);

  testWidgets('찍는 동안 이전 판정으로 완벽해요가 나오지 않고, 저장을 기다리지 않고 다시 안내한다', (
    tester,
  ) async {
    await pumpCamera(tester);
    expect(camera.streaming, 1);
    attitude.add(tiltedDown);
    await tester.pump();
    await frames(tester, inPlace: true);
    expect(signal(), ShootSignal.angleOff);

    await tester.tap(find.byType(ShutterButton));
    await settle(tester, () => camera.pictures == 1);
    expect(camera.pictures, 1);
    expect(camera.streaming, 0);
    expect(find.text('찍고 있어요. 폰을 움직이지 마세요'), findsOneWidget);

    // 찍는 동안 폰 각도가 맞아도 초록불이 아니다
    attitude.add(good);
    await tester.pump();
    expect(signal(), ShootSignal.paused);
    expect(find.text('완벽해요! 지금 찍으세요'), findsNothing);

    // 사진이 찍히면 저장이 끝나기 전이라도 인식을 다시 시작한다
    camera.picture.complete(XFile('/none/photo.jpg'));
    await settle(tester, () => camera.streaming == 1);
    expect(camera.streaming, 1);
    expect(tester.widget<ShutterButton>(find.byType(ShutterButton)).busy, true);
    await frames(tester, inPlace: false, count: 1);
    expect(signal(), ShootSignal.waiting);
    expect(find.text('찍을 사람을 화면에 비추세요'), findsOneWidget);

    // 저장이 끝나면 셔터가 풀린다
    capture.saved.complete(SaveResult.saved);
    await settle(tester, () => find.text('저장 완료').evaluate().isNotEmpty);
    expect(
      tester.widget<ShutterButton>(find.byType(ShutterButton)).busy,
      false,
    );
    await tester.pump(CaptureNoticeBar.duration);
  });

  testWidgets('저장 알림은 안내 문구·배율·셔터를 가리지 않고 3초 뒤 사라진다', (tester) async {
    await pumpCamera(tester);
    capture.saved.complete(SaveResult.saved);
    camera.picture.complete(XFile('/none/photo.jpg'));
    await tester.tap(find.byType(ShutterButton));
    await settle(tester, () => find.text('저장 완료').evaluate().isNotEmpty);
    await frames(tester, inPlace: false, count: 4);

    final notice = tester.getRect(find.byType(CaptureNoticeBar));
    for (final type in [CoachPill, ZoomSelector, ShutterButton]) {
      expect(notice.overlaps(tester.getRect(find.byType(type))), isFalse);
    }
    expect(find.text('보기'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(CaptureNoticeBar.duration);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('저장 완료'), findsNothing);
  });

  testWidgets('잠금 중 저장 알림에는 갤러리로 나가는 버튼이 없다', (tester) async {
    await pumpCamera(tester);
    container.read(guideLockProvider.notifier).lock();
    capture.saved.complete(SaveResult.saved);
    camera.picture.complete(XFile('/none/photo.jpg'));
    await tester.pump();
    await tester.tap(find.byType(ShutterButton));
    await settle(tester, () => find.text('저장 완료').evaluate().isNotEmpty);
    expect(find.text('보기'), findsNothing);
    await tester.pump(CaptureNoticeBar.duration);
  });

  testWidgets('자동 촬영은 같은 초록불에서 한 번만 찍는다', (tester) async {
    await pumpCamera(tester);
    attitude.add(good);
    await tester.pump();
    container.read(autoShutterProvider.notifier).toggle();
    await frames(tester, inPlace: true, count: 20);
    await settle(tester, () => camera.pictures == 1);
    container.read(compositionProvider.notifier).pause();
    await tester.pump();
    expect(signal(), ShootSignal.paused);
    camera.picture.complete(XFile('/none/photo.jpg'));
    capture.saved.complete(SaveResult.saved);
    await settle(tester, () => find.text('저장 완료').evaluate().isNotEmpty);
    expect(camera.pictures, 1);
    // 그대로 서 있으면 다시 찍지 않는다
    await frames(tester, inPlace: true, count: 20);
    expect(signal(), ShootSignal.ready);
    expect(
      tester.widget<ShutterButton>(find.byType(ShutterButton)).busy,
      false,
    );
    expect(camera.pictures, 1);
    await tester.pump(CaptureNoticeBar.duration);
  });
}
