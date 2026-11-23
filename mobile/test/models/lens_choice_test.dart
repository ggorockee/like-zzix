import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/lens_choice.dart';
import 'package:likezzix/models/zoom_range.dart';

CameraDescription cam(
  String name,
  CameraLensType type, [
  CameraLensDirection dir = CameraLensDirection.back,
]) => CameraDescription(
  name: name,
  lensDirection: dir,
  sensorOrientation: 90,
  lensType: type,
);

void main() {
  final iphone = [
    cam('ultra', CameraLensType.ultraWide),
    cam('tele', CameraLensType.telephoto),
    cam('wide', CameraLensType.wide),
    cam('front', CameraLensType.wide, CameraLensDirection.front),
  ];

  test('기본 카메라는 광각', () {
    expect(LensChoice.main(iphone, CameraLensDirection.back)?.name, 'wide');
    expect(LensChoice.main(iphone, CameraLensDirection.front)?.name, 'front');
    expect(LensChoice.main(const [], CameraLensDirection.back), isNull);
  });

  test('iPhone: 1배부터 시작하면 별도 초광각을 써서 0.5배 제공', () {
    const main = ZoomRange(1, 3);
    final ultra = LensChoice.ultraWide(iphone, CameraLensDirection.back, main);
    expect(ultra?.name, 'ultra');
    expect(main.withUltraWide.availableStops, [0.5, 1, 2, 3]);
    expect(LensChoice.deviceZoom(0.5, onUltraWide: true), 1);
    expect(LensChoice.deviceZoom(2, onUltraWide: false), 2);
    expect(
      LensChoice.ultraWide(iphone, CameraLensDirection.front, main),
      isNull,
    );
  });

  test('Android: 기본 카메라 줌이 0.5배를 포함하면 별도 카메라를 쓰지 않음', () {
    expect(
      LensChoice.ultraWide(
        iphone,
        CameraLensDirection.back,
        const ZoomRange(0.5, 3),
      ),
      isNull,
    );
  });
}
