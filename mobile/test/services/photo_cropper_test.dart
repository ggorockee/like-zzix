import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:likezzix/services/photo_cropper.dart';

void main() {
  test('가운데를 비율대로 자름', () {
    final r = PhotoCropper.region(720, 1280, 3 / 4)!;
    expect((r.left, r.top, r.width, r.height), (0, 160, 720, 960));
    final square = PhotoCropper.region(720, 1280, 1)!;
    expect((square.width, square.height, square.top), (720, 720, 280));
    expect(PhotoCropper.region(720, 1280, 9 / 16), isNull);
  });

  test('회전 정보가 있는 JPEG도 세로로 세워 자른다', () async {
    final dir = Directory.systemTemp.createTempSync('crop');
    addTearDown(() => dir.deleteSync(recursive: true));
    // 카메라처럼 가로 픽셀 + EXIF 90° 회전
    final source = img.Image(width: 128, height: 72)
      ..exif.imageIfd.orientation = 6;
    final path = '${dir.path}/a.jpg';
    File(path).writeAsBytesSync(img.encodeJpg(source));

    final out = await PhotoCropper.crop(path, 1);
    final result = img.decodeJpg(File(out).readAsBytesSync())!;
    expect(out, isNot(path));
    expect((result.width, result.height), (72, 72));
    expect(result.exif.imageIfd.orientation ?? 1, 1);
  });

  test('자르지 못하면 원본 경로', () async {
    expect(await PhotoCropper.crop('/없는/파일.jpg', 1), '/없는/파일.jpg');
  });
}
