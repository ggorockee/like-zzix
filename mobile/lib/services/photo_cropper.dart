import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 촬영한 사진을 뷰파인더 비율로 가운데 자르기 (뷰파인더에 보인 그대로 저장).
abstract final class PhotoCropper {
  /// [ratio]는 세로로 본 가로/세로. 새 파일 경로를 반환하고, 자를 필요가 없거나 실패하면 원본 경로.
  static Future<String> crop(String path, double ratio) async {
    try {
      final out = await compute(_cropFile, (path, ratio));
      return out ?? path;
    } on Object catch (e) {
      debugPrint('[Crop] 자르기 실패, 원본 저장: $e');
      return path;
    }
  }

  /// 가운데에서 [ratio] 비율로 자를 영역. 이미 같은 비율이면 null.
  @visibleForTesting
  static math.Rectangle<int>? region(int width, int height, double ratio) {
    final current = width / height;
    if ((current - ratio).abs() < 0.01) return null;
    final w = current > ratio ? (height * ratio).round() : width;
    final h = current > ratio ? height : (width / ratio).round();
    return math.Rectangle((width - w) ~/ 2, (height - h) ~/ 2, w, h);
  }

  static String? _cropFile((String, double) args) {
    final (path, ratio) = args;
    final decoded = img.decodeJpg(File(path).readAsBytesSync());
    if (decoded == null) return null;
    // 회전 정보(EXIF)를 실제 픽셀에 반영한 뒤 자른다
    final upright = img.bakeOrientation(decoded);
    final r = region(upright.width, upright.height, ratio);
    if (r == null) return null;
    final cropped = img.copyCrop(
      upright,
      x: r.left,
      y: r.top,
      width: r.width,
      height: r.height,
    );
    final out = path.replaceFirst(RegExp(r'(\.\w+)?$'), '_crop.jpg');
    File(out).writeAsBytesSync(img.encodeJpg(cropped, quality: 95));
    return out;
  }
}
