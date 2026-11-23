import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_theme.dart';
import 'screens/camera_screen.dart';
import 'screens/splash_screen.dart';

/// 앱(ProviderScope)마다 라우터를 새로 만든다.
/// 전역 GoRouter는 위젯 트리가 다시 만들어져도 이전 이동 기록이 남는다.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(path: '/', builder: (context, state) => const CameraScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class LikeZzixApp extends ConsumerWidget {
  const LikeZzixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '라익찍스',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // 카메라 화면은 글자가 너무 커지면 조작부가 화면을 벗어난다
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.35,
        child: child!,
      ),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
