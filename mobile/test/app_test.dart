import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/app.dart';
import 'package:likezzix/screens/camera_screen.dart';

void main() {
  testWidgets('앱 시작 시 카메라 화면으로 진입', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: LikeZzixApp()));
    expect(find.byType(CameraScreen), findsOneWidget);
  });
}
