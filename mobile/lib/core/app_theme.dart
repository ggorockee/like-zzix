import 'package:flutter/material.dart';

/// 라익찍스 색상 체계. 앱 UI는 유채색 3가지와 무채색(잉크·흰색)만 쓴다.
///
/// | 역할 | 색 | 쓰는 곳 |
/// |---|---|---|
/// | 핵심 | [coral] | 로고·스플래시·선택 상태·주요 버튼·어긋난 관절 |
/// | 서브 1 | [mint] | 신호: 지금 찍으면 됨 |
/// | 서브 2 | [amber] | 신호: 각도 이탈 |
/// | 무채색 | [ink]·[white] | 배경·반투명 판·글자·선 |
///
/// 나머지 상수는 모두 위 색의 투명도·밝기 단계다. 다른 파일에서 색을 새로 만들지 않는다
/// (`test/core/app_theme_test.dart`가 검사).
abstract final class AppTheme {
  /// 핵심 색
  static const coral = Color(0xFFFF5A7A);

  /// 서브 1: 구도·각도 일치 신호
  static const mint = Color(0xFF2EE6A0);

  /// 서브 2: 각도 이탈 신호
  static const amber = Color(0xFFFFD60A);

  /// 무채색: 배경
  static const ink = Color(0xFF14121A);

  /// 무채색: 글자·선
  static const white = Color(0xFFFFFFFF);

  // ink 단계 (카메라 위 반투명 판, 그림자)
  static const scrimSoft = Color(0x6114121A); // 38%
  static const scrim = Color(0x8A14121A); // 54%
  static const scrimStrong = Color(0xDE14121A); // 87%

  /// ink 위에 흰색 8%: 카드·칸 배경
  static const inkRaised = Color(0xFF27252C);

  // white 단계
  static const whiteMuted = Color(0xB3FFFFFF); // 70%
  static const whiteFaint = Color(0x3DFFFFFF); // 24%

  static final ThemeData dark = _build();

  static ThemeData _build() {
    // fromSeed는 시드에서 다른 색조를 파생하므로 모든 역할을 3색으로 직접 지정한다.
    const scheme = ColorScheme.dark(
      primary: coral,
      onPrimary: ink,
      primaryContainer: coral,
      onPrimaryContainer: ink,
      secondary: coral,
      onSecondary: ink,
      secondaryContainer: coral,
      onSecondaryContainer: ink,
      tertiary: mint,
      onTertiary: ink,
      tertiaryContainer: mint,
      onTertiaryContainer: ink,
      error: coral,
      onError: ink,
      surface: ink,
      onSurface: white,
      onSurfaceVariant: whiteMuted,
      surfaceContainerLowest: ink,
      surfaceContainerLow: ink,
      surfaceContainer: inkRaised,
      surfaceContainerHigh: inkRaised,
      surfaceContainerHighest: inkRaised,
      surfaceTint: Colors.transparent,
      inverseSurface: inkRaised,
      onInverseSurface: white,
      inversePrimary: coral,
      outline: whiteFaint,
      outlineVariant: whiteFaint,
      shadow: ink,
      scrim: ink,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      canvasColor: ink,
      // 셔터를 가리지 않도록 조작부 위에 띄운다
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: inkRaised,
        insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 190),
        contentTextStyle: TextStyle(color: white),
        actionTextColor: coral,
      ),
    );
  }
}
