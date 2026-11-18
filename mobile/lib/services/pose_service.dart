import 'dart:io' show Platform;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as mlkit;

import '../models/preset.dart';

/// 프레임 1장의 포즈 인식 결과.
@immutable
class PoseFrame {
  const PoseFrame(this.landmarks);

  /// 프리뷰 정규화 좌표(0~1, 화면에 보이는 방향·좌우반전 반영). 사람이 없으면 null.
  final List<PoseLandmark>? landmarks;
}

/// ML Kit 포즈 인식 (스트림 모드). 한 번에 한 프레임만 처리하고 [minInterval]로 제한.
class PoseService {
  PoseService({this.minInterval = const Duration(milliseconds: 90)});

  final Duration minInterval;
  final _detector = mlkit.PoseDetector(
    options: mlkit.PoseDetectorOptions(
      mode: mlkit.PoseDetectionMode.stream,
      model: mlkit.PoseDetectionModel.base,
    ),
  );

  bool _busy = false;
  bool _closed = false;

  // 디버그 빌드 진단: 2초마다 처리 프레임 수·인식 결과를 로그로 남김
  int _processed = 0;
  int _withPerson = 0;
  DateTime _statsSince = DateTime.now();
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  /// 이미지 스트림 형식 (ML Kit이 받는 형식으로 카메라에 요청).
  static ImageFormatGroup get imageFormatGroup =>
      Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

  /// 처리했으면 결과, 건너뛰었으면(처리 중/주기 미달/형식 불가) null.
  Future<PoseFrame?> process(
    CameraImage image,
    CameraDescription camera,
  ) async {
    final now = DateTime.now();
    if (_busy || _closed || now.difference(_last) < minInterval) return null;
    final rotation = imageRotation(sensorOrientation: camera.sensorOrientation);
    final input = _toInputImage(image, rotation);
    if (input == null) return null;

    _busy = true;
    _last = now;
    try {
      final poses = await _detector.processImage(input);
      _logStats(personFound: poses.isNotEmpty, image: image);
      if (poses.isEmpty) return const PoseFrame(null);
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final landmarks = poses.first.landmarks;
      return PoseFrame([
        for (final type in mlkit.PoseLandmarkType.values)
          if (landmarks[type] case final l?)
            () {
              final n = normalize(
                Offset(l.x, l.y),
                imageSize: size,
                rotation: rotation,
                lens: camera.lensDirection,
                isIOS: Platform.isIOS,
              );
              return PoseLandmark(n.dx, n.dy, l.likelihood);
            }()
          else
            const PoseLandmark(0, 0, 0),
      ]);
    } on Object catch (e) {
      debugPrint('[Pose] 인식 실패: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  void _logStats({required bool personFound, required CameraImage image}) {
    if (!kDebugMode) return;
    _processed++;
    if (personFound) _withPerson++;
    final elapsed = DateTime.now().difference(_statsSince);
    if (elapsed < const Duration(seconds: 2)) return;
    final fps = _processed / (elapsed.inMilliseconds / 1000);
    debugPrint(
      '[Pose] ${fps.toStringAsFixed(1)}fps, 사람 인식 $_withPerson/$_processed, '
      'frame ${image.width}x${image.height} ${image.format.group.name}',
    );
    _processed = 0;
    _withPerson = 0;
    _statsSince = DateTime.now();
  }

  Future<void> close() async {
    _closed = true;
    await _detector.close();
  }

  static mlkit.InputImage? _toInputImage(
    CameraImage image,
    mlkit.InputImageRotation rotation,
  ) {
    final format = mlkit.InputImageFormatValue.fromRawValue(image.format.raw);
    final supported = Platform.isAndroid
        ? format == mlkit.InputImageFormat.nv21
        : format == mlkit.InputImageFormat.bgra8888;
    if (format == null || !supported || image.planes.length != 1) return null;
    final plane = image.planes.first;
    return mlkit.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: mlkit.InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// 세로 고정 화면 기준 ML Kit 입력 회전값.
  /// ML Kit 공식 예제의 보정식에서 기기 방향이 항상 portraitUp(0°)이므로 센서 방향과 같다.
  @visibleForTesting
  static mlkit.InputImageRotation imageRotation({
    required int sensorOrientation,
  }) =>
      mlkit.InputImageRotationValue.fromRawValue(sensorOrientation % 360) ??
      mlkit.InputImageRotation.rotation0deg;

  /// ML Kit 좌표 → 프리뷰 정규화 좌표 (ML Kit 공식 예제의 translateX/Y와 동일한 규칙).
  /// 전면 카메라는 프리뷰가 좌우반전되어 보이므로 x를 뒤집는다.
  @visibleForTesting
  static Offset normalize(
    Offset point, {
    required Size imageSize,
    required mlkit.InputImageRotation rotation,
    required CameraLensDirection lens,
    required bool isIOS,
  }) {
    switch (rotation) {
      case mlkit.InputImageRotation.rotation90deg:
      case mlkit.InputImageRotation.rotation270deg:
        final w = isIOS ? imageSize.width : imageSize.height;
        final h = isIOS ? imageSize.height : imageSize.width;
        final x = point.dx / w;
        return Offset(
          rotation == mlkit.InputImageRotation.rotation270deg ? 1 - x : x,
          point.dy / h,
        );
      case mlkit.InputImageRotation.rotation0deg:
      case mlkit.InputImageRotation.rotation180deg:
        final x = point.dx / imageSize.width;
        return Offset(
          lens == CameraLensDirection.back ? x : 1 - x,
          point.dy / imageSize.height,
        );
    }
  }
}
