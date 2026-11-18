import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';

enum SaveResult { saved, permissionDenied, failed }

/// 촬영 결과를 기기 앨범("LikeZZIX")에 저장.
class CaptureService {
  static const album = 'LikeZZIX';

  Future<SaveResult> saveToGallery(String path) async {
    try {
      if (!await Gal.hasPermission(toAlbum: true) &&
          !await Gal.requestPermission(toAlbum: true)) {
        return SaveResult.permissionDenied;
      }
      await Gal.putImage(path, album: album);
      return SaveResult.saved;
    } on GalException catch (e) {
      debugPrint('[Capture] 저장 실패: ${e.type}');
      return e.type == GalExceptionType.permissionDenied
          ? SaveResult.permissionDenied
          : SaveResult.failed;
    }
  }
}
