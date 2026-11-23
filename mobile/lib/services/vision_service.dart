import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart' as ml;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'
    as face;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart'
    as pose;

import '../models/composition.dart';
import '../models/preset.dart';

/// 얼굴 하나 (프리뷰 0~1 좌표).
@immutable
class FaceObservation {
  const FaceObservation(this.box, this.yawDeg);

  final Rect box;

  /// 화면 오른쪽을 보면 +
  final double? yawDeg;
}

/// 프레임 1장의 인식 결과. 좌표는 프리뷰 0~1 (화면에 보이는 방향·좌우반전 반영).
@immutable
class VisionFrame {
  const VisionFrame({this.faces = const [], this.landmarks});

  final List<FaceObservation> faces;

  /// 포즈 관절 33개. 사람이 없거나 포즈를 쓰지 않았으면 null.
  final List<PoseLandmark>? landmarks;

  bool get hasPerson => faces.isNotEmpty || landmarks != null;
}

/// 어떤 인식기를 돌릴지. 얼굴은 가볍고 여러 명을 찾고, 포즈는 전신을 찾는다.
@immutable
class VisionNeeds {
  const VisionNeeds({
    this.face = false,
    this.body = false,
    this.minFaceSize = 0.12,
  });

  factory VisionNeeds.of(Preset preset) {
    final subjects = preset.template?.subjects;
    if (subjects == null) return const VisionNeeds(body: true);
    final faces = subjects.whereType<FaceSpec>();
    // 구도에 필요한 가장 작은 얼굴. 작을수록 인식 비용이 크게 늘어 3단계로만 나눈다.
    final smallest = faces.fold<double>(1, (m, s) => math.min(m, s.sizeMin));
    return VisionNeeds(
      face: faces.isNotEmpty,
      body: subjects.any((s) => s is BodySpec),
      minFaceSize: smallest >= 0.12
          ? 0.12
          : smallest >= 0.08
          ? 0.09
          : 0.06,
    );
  }

  final bool face;
  final bool body;

  /// 찾을 얼굴의 최소 크기 (이미지 폭 대비)
  final double minFaceSize;
}

/// ML Kit 얼굴·포즈 인식 (스트림 모드). 한 번에 한 프레임만 처리하고
/// 사람이 없을 때는 주기를 늦춰 발열을 줄인다. 인식기는 처음 필요할 때 만든다.
class VisionService {
  static const activeInterval = Duration(milliseconds: 60);
  static const idleInterval = Duration(milliseconds: 180);

  face.FaceDetector? _faces;
  double _minFaceSize = 0;
  late final _poses = pose.PoseDetector(
    options: pose.PoseDetectorOptions(
      mode: pose.PoseDetectionMode.stream,
      model: pose.PoseDetectionModel.base,
    ),
  );
  bool _posesUsed = false;

  bool _busy = false;
  bool _closed = false;
  Duration _interval = activeInterval;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  // 디버그·프로파일 빌드 진단: 2초마다 처리 프레임 수·인식 결과를 로그로 남김
  int _processed = 0;
  int _withPerson = 0;
  DateTime _statsSince = DateTime.now();

  /// 이미지 스트림 형식 (ML Kit이 받는 형식으로 카메라에 요청).
  static ImageFormatGroup get imageFormatGroup =>
      Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888;

  /// 처리했으면 결과, 건너뛰었으면(처리 중/주기 미달/형식 불가) null.
  Future<VisionFrame?> process(
    CameraImage image,
    CameraDescription camera,
    VisionNeeds needs,
  ) async {
    final now = DateTime.now();
    if (_busy || _closed || now.difference(_last) < _interval) return null;
    final rotation = imageRotation(sensorOrientation: camera.sensorOrientation);
    final input = _toInputImage(image, rotation);
    if (input == null) return null;

    _busy = true;
    _last = now;
    try {
      Offset map(double x, double y) => normalize(
        Offset(x, y),
        imageSize: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        lens: camera.lensDirection,
        isIOS: Platform.isIOS,
      );
      final frame = VisionFrame(
        faces: needs.face
            ? await _detectFaces(
                input,
                map,
                // Android 전면은 이미지가 프리뷰와 좌우 반대
                mirrored:
                    camera.lensDirection == CameraLensDirection.front &&
                    !Platform.isIOS,
                minFaceSize: needs.minFaceSize,
              )
            : const [],
        landmarks: needs.body ? await _detectPose(input, map) : null,
      );
      _interval = frame.hasPerson ? activeInterval : idleInterval;
      _logStats(frame, image);
      return frame;
    } on Object catch (e) {
      debugPrint('[Vision] 인식 실패: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// 최소 얼굴 크기가 다른 구도로 바뀌면 인식기를 새로 만든다.
  Future<face.FaceDetector> _faceDetector(double minFaceSize) async {
    final current = _faces;
    if (current != null && _minFaceSize == minFaceSize) return current;
    _minFaceSize = minFaceSize;
    final next = _faces = face.FaceDetector(
      options: face.FaceDetectorOptions(
        performanceMode: face.FaceDetectorMode.fast,
        minFaceSize: minFaceSize,
      ),
    );
    await current?.close();
    return next;
  }

  Future<List<FaceObservation>> _detectFaces(
    ml.InputImage input,
    Offset Function(double, double) map, {
    required bool mirrored,
    required double minFaceSize,
  }) async {
    final detector = await _faceDetector(minFaceSize);
    return [
      for (final f in await detector.processImage(input))
        FaceObservation(
          Rect.fromPoints(
            map(f.boundingBox.left, f.boundingBox.top),
            map(f.boundingBox.right, f.boundingBox.bottom),
          ),
          switch (f.headEulerAngleY) {
            final yaw? => mirrored ? -yaw : yaw,
            null => null,
          },
        ),
    ];
  }

  Future<List<PoseLandmark>?> _detectPose(
    ml.InputImage input,
    Offset Function(double, double) map,
  ) async {
    _posesUsed = true;
    final poses = await _poses.processImage(input);
    if (poses.isEmpty) return null;
    final landmarks = poses.first.landmarks;
    return [
      for (final type in pose.PoseLandmarkType.values)
        if (landmarks[type] case final l?)
          () {
            final n = map(l.x, l.y);
            return PoseLandmark(n.dx, n.dy, l.likelihood);
          }()
        else
          const PoseLandmark(0, 0, 0),
    ];
  }

  void _logStats(VisionFrame frame, CameraImage image) {
    if (kReleaseMode) return;
    _processed++;
    if (frame.hasPerson) _withPerson++;
    final elapsed = DateTime.now().difference(_statsSince);
    if (elapsed < const Duration(seconds: 2)) return;
    final fps = _processed / (elapsed.inMilliseconds / 1000);
    debugPrint(
      '[Vision] ${fps.toStringAsFixed(1)}fps, 사람 $_withPerson/$_processed, '
      '얼굴 ${frame.faces.length}, 포즈 ${frame.landmarks != null}, '
      'frame ${image.width}x${image.height}',
    );
    _processed = 0;
    _withPerson = 0;
    _statsSince = DateTime.now();
  }

  Future<void> close() async {
    _closed = true;
    await _faces?.close();
    if (_posesUsed) await _poses.close();
  }

  static ml.InputImage? _toInputImage(
    CameraImage image,
    ml.InputImageRotation rotation,
  ) {
    final format = ml.InputImageFormatValue.fromRawValue(image.format.raw);
    final supported = Platform.isAndroid
        ? format == ml.InputImageFormat.nv21
        : format == ml.InputImageFormat.bgra8888;
    if (format == null || !supported || image.planes.length != 1) return null;
    final plane = image.planes.first;
    return ml.InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: ml.InputImageMetadata(
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
  static ml.InputImageRotation imageRotation({
    required int sensorOrientation,
  }) =>
      ml.InputImageRotationValue.fromRawValue(sensorOrientation % 360) ??
      ml.InputImageRotation.rotation0deg;

  /// ML Kit 좌표 → 프리뷰 정규화 좌표 (ML Kit 공식 예제의 translateX/Y와 동일한 규칙).
  /// 전면 카메라는 프리뷰가 좌우반전되어 보이므로 x를 뒤집는다.
  @visibleForTesting
  static Offset normalize(
    Offset point, {
    required Size imageSize,
    required ml.InputImageRotation rotation,
    required CameraLensDirection lens,
    required bool isIOS,
  }) {
    switch (rotation) {
      case ml.InputImageRotation.rotation90deg:
      case ml.InputImageRotation.rotation270deg:
        final w = isIOS ? imageSize.width : imageSize.height;
        final h = isIOS ? imageSize.height : imageSize.width;
        final x = point.dx / w;
        return Offset(
          rotation == ml.InputImageRotation.rotation270deg ? 1 - x : x,
          point.dy / h,
        );
      case ml.InputImageRotation.rotation0deg:
      case ml.InputImageRotation.rotation180deg:
        final x = point.dx / imageSize.width;
        return Offset(
          lens == CameraLensDirection.back ? x : 1 - x,
          point.dy / imageSize.height,
        );
    }
  }
}
