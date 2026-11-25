import 'dart:ui' as ui;

import 'package:camera/camera.dart';
// ignore: depend_on_referenced_packages, camera가 다시 내보내지 않는 입력 타입
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraImageData, CameraImageFormat, CameraImagePlane;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:likezzix/services/preset_repository.dart';
import 'package:likezzix/services/vision_service.dart';

/// 실제 ML Kit을 불러 얼굴·포즈 인식이 앱을 죽이지 않는지 확인한다.
///
/// iOS는 모델 리소스 번들이 앱 타깃에 없으면 인식기를 처음 쓸 때 네이티브 예외로
/// 앱이 종료된다(1.0.0 빌드 3). 카메라가 없는 시뮬레이터에서도 확인할 수 있다.
///   flutter test integration_test/vision_smoke_test.dart -d SIMULATOR_ID
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const camera = CameraDescription(
    name: 'test',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 0,
  );

  /// 번들 예시 사진을 iOS 카메라 프레임(BGRA)과 같은 형식으로 만든다.
  Future<CameraImage> frame(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 720,
    );
    final image = (await codec.getNextFrame()).image;
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    final bgra = Uint8List(rgba.length);
    for (var i = 0; i < rgba.length; i += 4) {
      bgra[i] = rgba[i + 2];
      bgra[i + 1] = rgba[i + 1];
      bgra[i + 2] = rgba[i];
      bgra[i + 3] = rgba[i + 3];
    }
    return CameraImage.fromPlatformInterface(
      CameraImageData(
        // kCVPixelFormatType_32BGRA
        format: const CameraImageFormat(
          ImageFormatGroup.bgra8888,
          raw: 1111970369,
        ),
        width: image.width,
        height: image.height,
        planes: [
          CameraImagePlane(
            bytes: bgra,
            bytesPerRow: image.width * 4,
            width: image.width,
            height: image.height,
          ),
        ],
      ),
    );
  }

  Future<VisionFrame?> run(String asset, VisionNeeds needs) async {
    final vision = VisionService();
    final image = await frame(asset);
    VisionFrame? result;
    // 스트림 모드라 몇 프레임 지나야 잡히는 경우가 있다
    for (var i = 0; i < 10 && !(result?.hasPerson ?? false); i++) {
      result = await vision.process(image, camera, needs) ?? result;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await vision.close();
    return result;
  }

  testWidgets('얼굴 구도(중앙 배치·삼분할): 얼굴을 찾는다', (_) async {
    for (final id in ['cmp-center', 'cmp-thirds']) {
      final result = await run(
        'assets/presets/reference/$id.jpg',
        const VisionNeeds(face: true),
      );
      expect(result?.faces, isNotEmpty, reason: id);
    }
  });

  testWidgets('전신 구도: 포즈를 찾는다', (_) async {
    final result = await run(
      'assets/presets/reference/cmp-s-pose.jpg',
      const VisionNeeds(body: true),
    );
    expect(result?.landmarks, isNotNull);
  });

  testWidgets('모든 구도를 차례로 바꿔도 앱이 종료되지 않는다', (_) async {
    final vision = VisionService();
    final image = await frame('assets/presets/reference/cmp-center.jpg');
    final templates = await PresetRepository().loadTemplates();
    expect(templates, hasLength(23));
    for (final preset in templates) {
      await Future<void>.delayed(VisionService.idleInterval * 1.2);
      final result = await vision.process(
        image,
        camera,
        VisionNeeds.of(preset),
      );
      expect(result, isNotNull, reason: preset.id);
    }
    await vision.close();
  });
}
