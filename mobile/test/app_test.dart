import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/app.dart';
import 'package:likezzix/services/app_initializer.dart';
import 'package:likezzix/providers/ad_providers.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';
import 'package:likezzix/screens/splash_screen.dart';

void main() {
  Widget app({Future<AppBootstrap> Function()? init}) => ProviderScope(
    overrides: [
      availableCamerasProvider.overrideWith((ref) async => []),
      appInitProvider.overrideWith(
        (ref) => (init ?? () async => AppBootstrap.fallback)(),
      ),
    ],
    child: const LikeZzixApp(),
  );

  testWidgets('스플래시 → 최소 표시 시간 후 카메라 화면', (tester) async {
    await tester.pumpWidget(app());
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('라익찍스'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1000));
    expect(find.byType(SplashScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
    expect(find.byType(CameraScreen), findsOneWidget);
  });

  testWidgets('초기화가 오래 걸려도 최대 대기 후 넘어감', (tester) async {
    await tester.pumpWidget(
      app(
        init: () => Future.delayed(
          const Duration(seconds: 30),
          () => AppBootstrap.fallback,
        ),
      ),
    );
    await tester.pump(
      SplashScreen.maximumWait + const Duration(milliseconds: 100),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CameraScreen), findsOneWidget);
    // 남은 초기화 타이머 정리
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('카메라가 없는 환경: 안내 문구와 촬영 컨트롤 표시', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(SplashScreen.minimumDuration);
    await tester.pumpAndSettle();

    expect(find.text('이 기기에서는 카메라를 사용할 수 없어요'), findsOneWidget);
    expect(find.byTooltip('구도 프리셋'), findsOneWidget);
    expect(find.byTooltip('갤러리'), findsOneWidget);
    expect(find.bySemanticsLabel('촬영'), findsOneWidget);
    // 카메라가 없으면 렌즈 전환 비활성
    final lens = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.cameraswitch_outlined),
    );
    expect(lens.onPressed, isNull);
  });
}
