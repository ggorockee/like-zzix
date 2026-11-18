import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/zoom_range.dart';

void main() {
  test('Z Flip5 후면(0.5~10): 0.5~3배로 제한, 버튼 4개', () {
    final r = ZoomRange.fromDevice(0.5, 10);
    expect(r, const ZoomRange(0.5, 3));
    expect(r.availableStops, [0.5, 1, 2, 3]);
    expect(r.clamp(5), 3);
    expect(r.clamp(0.3), 0.5);
  });

  test('초광각 없는 카메라(1~8): 0.5 버튼 없음', () {
    final r = ZoomRange.fromDevice(1, 8);
    expect(r.availableStops, [1, 2, 3]);
  });

  test('줌 미지원(1~1): 버튼 1개 → 선택기 숨김 대상', () {
    expect(ZoomRange.fromDevice(1, 1).availableStops, [1]);
  });

  test('활성 버튼: 현재 배율 이하의 가장 큰 버튼', () {
    const r = ZoomRange(0.5, 3);
    expect(r.activeStop(0.5), 0.5);
    expect(r.activeStop(0.8), 0.5);
    expect(r.activeStop(1.0), 1);
    expect(r.activeStop(1.9), 1);
    expect(r.activeStop(2.0), 2);
    expect(r.activeStop(3.0), 3);
  });

  test('라벨', () {
    expect(ZoomRange.label(0.5), '0.5');
    expect(ZoomRange.label(1), '1');
    expect(ZoomRange.label(1, current: 1.43), '1.4x');
    expect(ZoomRange.label(2, current: 2), '2x');
  });
}
