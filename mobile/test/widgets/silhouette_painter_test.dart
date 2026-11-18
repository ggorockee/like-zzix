import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/widgets/silhouette_painter.dart';

void main() {
  test('세로로 긴 화면: 프레임은 가로를 꽉 채우고 세로 가운데', () {
    final rect = SilhouettePainter.frameRect(const Size(390, 844), 3 / 4);
    expect(rect.width, 390);
    expect(rect.height, closeTo(520, 1e-9));
    expect(rect.top, closeTo((844 - 520) / 2, 1e-9));
  });

  test('가로로 넓은 칸: 프레임은 세로를 꽉 채우고 가로 가운데', () {
    final rect = SilhouettePainter.frameRect(const Size(200, 100), 3 / 4);
    expect(rect.height, 100);
    expect(rect.width, closeTo(75, 1e-9));
    expect(rect.left, closeTo(62.5, 1e-9));
  });
}
