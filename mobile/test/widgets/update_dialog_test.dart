import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/app_version.dart';
import 'package:likezzix/widgets/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(
    WidgetTester tester,
    UpdatePolicy policy, {
    required ValueSetter<bool> done,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await UpdatePrompt.showIfNeeded(
                context,
                policy: policy,
                current: AppVersion.parse('1.0.0'),
              );
              done(true);
            },
            child: const Text('start'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
  }

  UpdatePolicy policy({String min = '0.0.0', String latest = '0.0.0'}) =>
      UpdatePolicy(
        minVersion: AppVersion.parse(min),
        latestVersion: AppVersion.parse(latest),
        storeUrl: 'https://play.google.com/store/apps/details?id=x',
      );

  testWidgets('강제 업데이트: 닫을 수 없고 앱 진행이 멈춤', (tester) async {
    var finished = false;
    await pump(tester, policy(min: '2.0.0'), done: (v) => finished = v);

    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    expect(find.text('나중에'), findsNothing);

    // 바깥 탭·뒤로가기로 닫히지 않음
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    await navigator.maybePop();
    await tester.pumpAndSettle();
    expect(find.text('업데이트가 필요해요'), findsOneWidget);
    expect(finished, isFalse);
  });

  testWidgets('선택 업데이트: "나중에" 후 같은 버전은 다시 묻지 않음', (tester) async {
    var finished = false;
    await pump(tester, policy(latest: '1.1.0'), done: (v) => finished = v);
    expect(find.text('새 버전이 있어요'), findsOneWidget);

    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_dismissed_version'), '1.1.0');

    finished = false;
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('새 버전이 있어요'), findsNothing);
    expect(finished, isTrue);
  });

  testWidgets('정책이 없으면 팝업 없이 진행', (tester) async {
    var finished = false;
    await pump(tester, UpdatePolicy.none, done: (v) => finished = v);
    expect(find.byType(AlertDialog), findsNothing);
    expect(finished, isTrue);
  });
}
