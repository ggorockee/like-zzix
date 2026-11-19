import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// integration_test/store_screenshots_test.dart가 찍은 화면을 build/store_screenshots/에 저장.
///   flutter drive --driver=test_driver/screenshot_driver.dart \
///     --target=integration_test/store_screenshots_test.dart -d SIMULATOR_ID
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/store_screenshots/$name.png');
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    return true;
  },
);
