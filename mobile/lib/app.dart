import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/app_theme.dart';
import 'screens/camera_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';

/// 앱(ProviderScope)마다 라우터를 새로 만든다.
/// 전역 GoRouter는 위젯 트리가 다시 만들어져도 이전 이동 기록이 남는다.
final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const CameraScreen(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'login',
                builder: (context, state) => const LoginScreen(),
              ),
            ],
          ),
        ],
      ),
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
      routerConfig: ref.watch(routerProvider),
    );
  }
}
