import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

enum SaveResult { saved, permissionDenied, failed }

/// 촬영 결과를 기기 사진 앱에 저장.
///
/// - Android: "LikeZZIX" 앨범
/// - iOS: 앨범을 만들려면 전체 사진 접근 권한이 필요하므로, 추가 전용 권한으로 사진 앱에만 저장
class CaptureService {
  static const album = 'LikeZZIX';

  static final bool _toAlbum = Platform.isAndroid;

  Future<SaveResult> saveToGallery(String path) async {
    try {
      if (!await Gal.hasPermission(toAlbum: _toAlbum) &&
          !await Gal.requestPermission(toAlbum: _toAlbum)) {
        return SaveResult.permissionDenied;
      }
      await Gal.putImage(path, album: _toAlbum ? album : null);
      return SaveResult.saved;
    } on GalException catch (e) {
      debugPrint('[Capture] 저장 실패: ${e.type}');
      return e.type == GalExceptionType.permissionDenied
          ? SaveResult.permissionDenied
          : SaveResult.failed;
    }
  }

  /// 기기 기본 갤러리 앱 열기.
  Future<void> openGallery() async {
    try {
      await Gal.open();
    } on Object catch (e) {
      debugPrint('[Capture] 갤러리 열기 실패: $e');
    }
  }
}
