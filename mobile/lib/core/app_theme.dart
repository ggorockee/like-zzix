import 'package:flutter/material.dart';

/// 카메라 앱 특성상 어두운 테마 단일 사용.
abstract final class AppTheme {
  static const brand = Color(0xFFFF5A7A);
  static const matchGreen = Color(0xFF34C759);

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: Colors.black,
  );
}
