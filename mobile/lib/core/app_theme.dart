import 'package:flutter/material.dart';

/// 라익찍스 색상 체계. 앱 UI는 아래 3가지 색(+ 글자·선용 흰색)만 쓴다.
///
/// | 역할 | 색 | 쓰는 곳 |
/// |---|---|---|
/// | 핵심 | [coral] | 로고·스플래시·선택 상태·주요 버튼·"아직 안 맞음" |
/// | 서브 1 | [mint] | 구도·각도가 맞았을 때만 |
/// | 서브 2 | [ink] | 배경·시트·카메라 위 반투명 판·코랄/민트 위 글자 |
///
/// 나머지 상수는 모두 위 색의 투명도·밝기 단계다. 다른 파일에서 색을 새로 만들지 않는다
/// (`test/core/app_theme_test.dart`가 검사).
abstract final class AppTheme {
  /// 핵심 색
  static const coral = Color(0xFFFF5A7A);

  /// 서브 1: 구도 일치
  static const mint = Color(0xFF2EE6A0);

  /// 서브 2: 배경
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
    );
  }
}
