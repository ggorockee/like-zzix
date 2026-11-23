// 로고 PNG 생성기. 실행: flutter test tool/generate_branding.dart
//
// LogoMarkPainter 하나로 앱 아이콘·적응형 아이콘·스플래시 이미지를 만든다.
// 결과는 assets/branding/ 에 저장되고, flutter_launcher_icons / flutter_native_splash가 사용한다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/widgets/logo_mark.dart';

Future<void> _render(String path, int size, LogoMarkPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('브랜딩 이미지 생성', () async {
    const dir = 'assets/branding';
    // iOS/기본 아이콘: 꽉 찬 코랄 (모서리는 OS가 둥글게 자름)
    await _render('$dir/icon.png', 1024, const LogoMarkPainter());
    // Android 적응형 아이콘: 배경 코랄 + 투명 전경(안전 영역 안으로 축소)
    await _render(
      '$dir/icon_background.png',
      1024,
      const LogoMarkPainter(paintMark: false),
    );
    await _render(
      '$dir/icon_foreground.png',
      1024,
      const LogoMarkPainter(
        background: LogoBackground.none,
        contentScale: 0.78,
      ),
    );
    // 스플래시: 코랄 배경 위 마크 (투명 배경)
    await _render(
      '$dir/splash_logo.png',
      768,
      const LogoMarkPainter(background: LogoBackground.none),
    );
    // Android 12 스플래시 아이콘: 원형 마스크(지름 2/3) 안에 들어가도록 축소
    await _render(
      '$dir/splash_logo_android12.png',
      1152,
      const LogoMarkPainter(
        background: LogoBackground.none,
        contentScale: 0.62,
      ),
    );
    // 미리보기용: 둥근 아이콘
    await _render(
      '$dir/logo_preview.png',
      512,
      const LogoMarkPainter(background: LogoBackground.rounded),
    );
    // 관리자 콘솔 파비콘
    await _render(
      '../admin/public/favicon.png',
      512,
      const LogoMarkPainter(background: LogoBackground.rounded),
    );
  });
}
