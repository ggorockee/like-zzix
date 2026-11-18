import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/core/ad_unit_ids.dart';

void main() {
  test('테스트 빌드는 Google 테스트 광고 단위 ID 사용', () {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final format in AdFormat.values) {
        final id = AdUnitIds.of(format, platform: platform, useTestIds: true);
        expect(id, startsWith('ca-app-pub-3940256099942544/'));
      }
    }
  });

  test('릴리스 ID가 주입되지 않으면 null (광고 로드 안 함)', () {
    for (final format in AdFormat.values) {
      expect(
        AdUnitIds.of(
          format,
          platform: TargetPlatform.android,
          useTestIds: false,
        ),
        isNull,
      );
    }
  });

  test('지원하지 않는 플랫폼은 null', () {
    expect(
      AdUnitIds.of(
        AdFormat.native,
        platform: TargetPlatform.linux,
        useTestIds: true,
      ),
      isNull,
    );
  });
}
