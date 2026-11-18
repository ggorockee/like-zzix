import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/screens/splash_screen.dart';

void main() {
  test('바닥에서 시작해 중간에 가장 높고 다시 바닥', () {
    expect(BouncingLogo.heightAt(0), closeTo(0, 1e-9));
    expect(BouncingLogo.heightAt(0.5), closeTo(1, 1e-9));
    expect(BouncingLogo.heightAt(1), closeTo(0, 1e-9));
  });

  test('바닥에서만 찌그러짐', () {
    expect(BouncingLogo.squashAt(0), closeTo(1, 1e-9));
    expect(BouncingLogo.squashAt(0.5), 0);
    expect(BouncingLogo.squashAt(0.3), 0);
  });
}
