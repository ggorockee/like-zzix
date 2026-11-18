import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/widgets/reference_image.dart';

void main() {
  group('resolveReferenceUrl', () {
    test('상대 경로를 API 주소 기준으로 붙인다', () {
      expect(
        resolveReferenceUrl(
          '/v1/presets/a/image?v=1',
          'https://like-zzix-api.woohalabs.com',
        ),
        'https://like-zzix-api.woohalabs.com/v1/presets/a/image?v=1',
      );
    });
    test('절대 URL은 그대로', () {
      expect(
        resolveReferenceUrl('https://x.test/a.jpg', ''),
        'https://x.test/a.jpg',
      );
    });
    test('경로나 API 주소가 없으면 null', () {
      expect(resolveReferenceUrl(null, 'https://a.test'), isNull);
      expect(resolveReferenceUrl('/v1/x', ''), isNull);
    });
  });
}
