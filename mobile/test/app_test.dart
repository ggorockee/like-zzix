import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/app.dart';
import 'package:likezzix/providers/auth_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';

import 'fakes/auth_fakes.dart';

void main() {
  late FakeAuthApi api;

  setUp(() => api = FakeAuthApi());

  Widget app(FakeAuthSessionStore store) => ProviderScope(
    overrides: [
      authSessionStoreProvider.overrideWithValue(store),
      authApiProvider.overrideWithValue(api),
      snsSignInProvider.overrideWithValue(FakeSnsSignIn()),
    ],
    child: const LikeZzixApp(),
  );

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
  }

  testWidgets('앱 시작 시 카메라 화면으로 진입', (tester) async {
    await tester.pumpWidget(app(FakeAuthSessionStore()));
    expect(find.byType(CameraScreen), findsOneWidget);
  });

  testWidgets('설정 → 로그인 → 카카오 로그인 후 설정으로 복귀', (tester) async {
    api.signInResult = session(owner: user(isStaff: true, name: '운영자'));
    await tester.pumpWidget(app(FakeAuthSessionStore()));
    await openSettings(tester);

    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('카카오로 계속하기'), findsOneWidget);
    expect(find.text('Google로 계속하기'), findsOneWidget);

    await tester.tap(find.text('카카오로 계속하기'));
    await tester.pumpAndSettle();

    expect(find.text('운영자'), findsOneWidget);
    expect(find.text('카카오 로그인 · 스태프 · 광고 없음'), findsOneWidget);
  });

  testWidgets('슈퍼계정 로그인 상태 표시 및 로그아웃', (tester) async {
    final store = FakeAuthSessionStore(session(owner: user(isSuperuser: true)));
    await tester.pumpWidget(app(store));
    await openSettings(tester);

    expect(find.text('카카오 로그인 · 슈퍼계정 · 광고 없음'), findsOneWidget);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(store.saved, isNull);
    expect(find.text('카카오 · Google · Apple'), findsOneWidget);
  });

  testWidgets('회원 탈퇴는 확인 후 진행', (tester) async {
    final store = FakeAuthSessionStore(session(access: 'ax'));
    await tester.pumpWidget(app(store));
    await openSettings(tester);

    await tester.tap(find.text('회원 탈퇴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(store.saved, isNotNull);

    await tester.tap(find.text('회원 탈퇴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('탈퇴'));
    await tester.pumpAndSettle();
    expect(api.deletedWith, ['ax']);
    expect(store.saved, isNull);
  });
}
