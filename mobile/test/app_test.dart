import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/app.dart';
import 'package:likezzix/providers/camera_providers.dart';
import 'package:likezzix/screens/camera_screen.dart';

void main() {
  testWidgets('카메라가 없는 환경: 안내 문구와 촬영 컨트롤 표시', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [availableCamerasProvider.overrideWith((ref) async => [])],
        child: const LikeZzixApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CameraScreen), findsOneWidget);
    expect(find.text('이 기기에서는 카메라를 사용할 수 없어요'), findsOneWidget);
    expect(find.byTooltip('구도 프리셋'), findsOneWidget);
    expect(find.bySemanticsLabel('촬영'), findsOneWidget);
    // 카메라가 없으면 렌즈 전환 비활성
    final lens = tester.widget<IconButton>(find.byType(IconButton));
    expect(lens.onPressed, isNull);
  });
}
