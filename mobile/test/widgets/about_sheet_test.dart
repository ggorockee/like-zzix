import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/providers/ad_providers.dart';
import 'package:likezzix/services/app_initializer.dart';
import 'package:likezzix/widgets/about_sheet.dart';

void main() {
  testWidgets('개인정보처리방침·고객지원·라이선스를 볼 수 있다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appInitProvider.overrideWith((ref) async => AppBootstrap.fallback),
        ],
        child: const MaterialApp(home: Scaffold(body: AboutSheet())),
      ),
    );
    await tester.pumpAndSettle();
    for (final t in ['개인정보처리방침', '고객지원·문의', '오픈소스 라이선스']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // 동의 변경이 필요 없는 지역에서는 숨김
    expect(find.text('광고 개인정보 설정'), findsNothing);

    await tester.tap(find.text('오픈소스 라이선스'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });

  test('정책 주소는 운영 도메인 https', () {
    for (final u in [AboutSheet.privacyUrl, AboutSheet.supportUrl]) {
      expect(u, startsWith('https://like-zzix.woohalabs.com/'));
    }
  });
}
