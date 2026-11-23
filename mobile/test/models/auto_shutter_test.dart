import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/auto_shutter.dart';

void main() {
  late AutoShutter shutter;
  late int shots;

  void create() {
    shots = 0;
    shutter = AutoShutter(onFire: () => shots++);
    addTearDown(shutter.dispose);
  }

  const ms = Duration(milliseconds: 1);

  testWidgets('초록불 0.6초 유지되면 한 번 촬영', (tester) async {
    create();
    shutter.update(ready: true, enabled: true);
    expect(shutter.counting.value, isTrue);
    await tester.pump(ms * 590);
    expect(shots, 0);
    await tester.pump(ms * 20);
    expect(shots, 1);
    expect(shutter.counting.value, isFalse);

    // 계속 초록불이어도 다시 찍지 않음
    shutter.update(ready: true, enabled: true);
    await tester.pump(const Duration(seconds: 2));
    expect(shots, 1);

    // 초록불이 꺼졌다 켜지면 다시 촬영
    shutter.update(ready: false, enabled: true);
    shutter.update(ready: true, enabled: true);
    await tester.pump(ms * 610);
    expect(shots, 2);
  });

  testWidgets('0.6초 전에 초록불이 꺼지면 처음부터', (tester) async {
    create();
    shutter.update(ready: true, enabled: true);
    await tester.pump(ms * 500);
    shutter.update(ready: false, enabled: true);
    shutter.update(ready: true, enabled: true);
    await tester.pump(ms * 500);
    expect(shots, 0);
    await tester.pump(ms * 110);
    expect(shots, 1);
  });

  testWidgets('꺼져 있으면 촬영하지 않음', (tester) async {
    create();
    shutter.update(ready: true, enabled: false);
    await tester.pump(const Duration(seconds: 2));
    expect(shots, 0);
  });

  testWidgets('직접 찍은 뒤에는 같은 초록불에서 자동으로 또 찍지 않음', (tester) async {
    create();
    shutter.update(ready: true, enabled: true);
    await tester.pump(ms * 300);
    shutter.markShot();
    shutter.update(ready: true, enabled: false);
    shutter.update(ready: true, enabled: true);
    await tester.pump(const Duration(seconds: 2));
    expect(shots, 0);
  });
}
