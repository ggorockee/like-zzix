import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/app_version.dart';

void main() {
  test('버전 파싱: 빌드 번호·접미사 무시, 잘못된 값은 0', () {
    expect(AppVersion.parse('1.2.3'), const AppVersion(1, 2, 3));
    expect(AppVersion.parse('1.2.3+45'), const AppVersion(1, 2, 3));
    expect(AppVersion.parse('2.0'), const AppVersion(2, 0, 0));
    expect(AppVersion.parse(''), AppVersion.zero);
    expect(AppVersion.parse('abc'), AppVersion.zero);
  });

  test('비교는 숫자 기준 (문자열 비교 아님)', () {
    expect(AppVersion.parse('1.10.0') < AppVersion.parse('1.9.0'), isFalse);
    expect(AppVersion.parse('1.9.9') < AppVersion.parse('1.10.0'), isTrue);
  });

  group('UpdatePolicy', () {
    UpdatePolicy policy({
      String min = '0.0.0',
      String latest = '0.0.0',
      String url = 'https://store',
    }) => UpdatePolicy(
      minVersion: AppVersion.parse(min),
      latestVersion: AppVersion.parse(latest),
      storeUrl: url,
    );
    final current = AppVersion.parse('1.2.0');

    test('기본값(0.0.0)이면 안내 없음', () {
      expect(UpdatePolicy.none.evaluate(current), UpdateRequirement.none);
    });

    test('최소 버전보다 낮으면 강제', () {
      expect(policy(min: '1.3.0').evaluate(current), UpdateRequirement.force);
    });

    test('최신 버전보다 낮으면 선택', () {
      expect(
        policy(latest: '1.2.1').evaluate(current),
        UpdateRequirement.optional,
      );
    });

    test('같거나 높으면 없음', () {
      expect(
        policy(min: '1.2.0', latest: '1.2.0').evaluate(current),
        UpdateRequirement.none,
      );
    });

    test('스토어 링크가 없으면 선택 업데이트는 띄우지 않음 (강제는 유지)', () {
      expect(
        policy(latest: '2.0.0', url: '').evaluate(current),
        UpdateRequirement.none,
      );
      expect(
        policy(min: '2.0.0', url: '').evaluate(current),
        UpdateRequirement.force,
      );
    });
  });
}
