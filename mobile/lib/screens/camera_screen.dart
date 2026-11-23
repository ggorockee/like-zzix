import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../models/auto_shutter.dart';
import '../models/coach.dart';
import '../models/angle_state.dart';
import '../models/guide_motion.dart';
import '../models/lens_choice.dart';
import '../models/preset.dart';
import '../providers/camera_providers.dart';
import '../providers/preset_providers.dart';
import '../services/capture_service.dart';
import '../models/preview_transform.dart';
import '../models/composition_fit.dart';
import '../models/subject.dart';
import '../models/zoom_range.dart';
import '../providers/ad_providers.dart';
import '../providers/api_providers.dart';
import '../providers/attitude_providers.dart';
import '../providers/guide_motion_provider.dart';
import '../providers/shooting_providers.dart';
import '../providers/composition_providers.dart';
import '../services/photo_cropper.dart';
import '../services/vision_service.dart';
import '../services/telemetry_service.dart';
import '../widgets/about_sheet.dart';
import '../widgets/angle_indicator.dart';
import '../widgets/camera_preview_fullscreen.dart';
import '../widgets/frame_guide.dart';
import '../widgets/gallery_button.dart';
import '../widgets/guide_card.dart';
import '../widgets/coach_pill.dart';
import '../widgets/composition_card.dart';
import '../widgets/dynamic_frame.dart';
import '../widgets/lock_button.dart';
import '../widgets/opacity_slider.dart';
import '../widgets/preset_bottom_sheet.dart';
import '../widgets/reference_image.dart';
import '../widgets/reference_overlay.dart';
import '../widgets/reference_pip.dart';
import '../widgets/shutter_button.dart';
import '../widgets/zoom_selector.dart';

/// 메인 카메라 화면: 뷰파인더(프리뷰 + 가이드) + 설정 컨트롤 + 촬영 컨트롤.
/// 잠금 중에는 셔터·배율·잠금 해제만 남긴다.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

enum _CameraIssue { none, unavailable, permissionDenied, failed }

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraLensDirection _lens = CameraLensDirection.back;
  _CameraIssue _issue = _CameraIssue.none;
  bool _capturing = false;
  bool _switching = false;
  bool _flash = false;

  /// 권한 창에서 방금 거부함: 창이 닫히며 오는 resumed에서는 다시 묻지 않는다.
  bool _permissionAsked = false;

  /// 앱이 포그라운드인지. 권한 팝업 등으로 inactive일 때 열린 카메라는 바로 닫는다.
  bool _foreground = true;

  /// 진행 중인 카메라 열기 작업 (동시에 두 번 열지 않도록 직렬화).
  Future<void>? _opening;

  /// 실시간 인물 인식 (프리셋을 골랐을 때만 이미지 스트림 실행)
  final _vision = VisionService();
  bool _streaming = false;

  /// 프레임 좌표 변환에 쓰는 마지막 뷰파인더 크기
  Size _finderSize = Size.zero;

  /// 별도 초광각 카메라 (iOS). 없으면 null.
  CameraDescription? _ultraWide;
  bool _onUltraWide = false;

  /// 프리셋 시트가 열려 있으면 자동·볼륨 촬영을 막는다.
  bool _sheetOpen = false;

  late final _autoShutter = AutoShutter(
    onFire: () => unawaited(_capture(AppEvent.autoCaptured)),
  );
  StreamSubscription<void>? _volume;

  /// 줌 (기기 지원 범위 ∩ 0.5~3배)
  ZoomRange _zoomRange = ZoomRange.none;
  double _zoom = 1;
  double _pinchStartZoom = 1;

  /// 이번 세션에 마지막으로 찍은 사진 (갤러리 버튼 썸네일)
  String? _lastPhotoPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_startCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller?.dispose());
    unawaited(_vision.close());
    unawaited(_volume?.cancel());
    _autoShutter.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[Camera] lifecycle: $state');
    switch (state) {
      case AppLifecycleState.inactive || AppLifecycleState.paused:
        // 백그라운드/권한 팝업: 카메라를 놓아준다.
        _foreground = false;
        _syncShutterTriggers();
        final controller = _controller;
        if (controller == null) return;
        _streaming = false;
        setState(() => _controller = null);
        unawaited(controller.dispose());
      case AppLifecycleState.resumed:
        _foreground = true;
        // Android는 열기를 시도할 때마다 권한을 다시 묻는다: 거부한 뒤에는
        // 설정에서 돌아왔을 때만 다시 시도한다
        if (_controller == null && !_permissionAsked) {
          unawaited(_startCamera());
        }
        _permissionAsked = false;
      case AppLifecycleState.detached || AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _startCamera() => _opening ??= _openCamera().whenComplete(() {
    _opening = null;
    // 여는 동안 앱이 잠깐 비활성이었다가(권한 창 등) 그새 돌아왔으면 다시 연다
    if (mounted &&
        _foreground &&
        _controller == null &&
        _issue == _CameraIssue.none) {
      unawaited(_startCamera());
    }
  });

  Future<void> _openCamera() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await ref.read(availableCamerasProvider.future);
    } on Object {
      if (mounted) setState(() => _issue = _CameraIssue.unavailable);
      _record(AppEvent.cameraUnavailable);
      return;
    }
    if (cameras.isEmpty) {
      if (mounted) setState(() => _issue = _CameraIssue.unavailable);
      _record(AppEvent.cameraUnavailable);
      return;
    }
    final description = LensChoice.main(cameras, _lens) ?? cameras.first;
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: VisionService.imageFormatGroup,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      if (!mounted) return;
      _permissionAsked = e.code.startsWith('CameraAccess') && !_foreground;
      setState(
        () => _issue = e.code.startsWith('CameraAccess')
            ? _CameraIssue.permissionDenied
            : _CameraIssue.failed,
      );
      _record(AppEvent.cameraUnavailable);
      return;
    }
    // 초기화 중 화면을 떠났으면 닫는다 (resumed에서 다시 연다).
    if (!mounted || !_foreground) {
      debugPrint('[Camera] 초기화 완료 시점에 비활성 → 닫음');
      await controller.dispose();
      return;
    }
    final zoomRange = await _readZoomRange(controller);
    final old = _controller;
    _streaming = false;
    setState(() {
      _controller = controller;
      _setLens(description.lensDirection);
      _issue = _CameraIssue.none;
      _useLensRange(cameras, zoomRange);
    });
    _syncShutterTriggers();
    await old?.dispose();
    await _applyZoom(controller);
    await _syncPoseStream();
  }

  void _setLens(CameraLensDirection lens) {
    _lens = lens;
    if (mounted) ref.read(activeLensProvider.notifier).set(lens);
  }

  // ---------------------------------------------------------------------------
  // 줌
  // ---------------------------------------------------------------------------

  Future<ZoomRange> _readZoomRange(CameraController controller) async {
    try {
      final range = ZoomRange.fromDevice(
        await controller.getMinZoomLevel(),
        await controller.getMaxZoomLevel(),
      );
      debugPrint(
        '[Camera] ${controller.description.name} 줌 ${range.min}~${range.max}',
      );
      return range;
    } on CameraException {
      return ZoomRange.none;
    }
  }

  Future<void> _applyZoom(CameraController controller) async {
    try {
      await controller.setZoomLevel(
        LensChoice.deviceZoom(_zoom, onUltraWide: _onUltraWide),
      );
    } on CameraException catch (e) {
      debugPrint('[Camera] 줌 설정 실패: ${e.code}');
    }
  }

  /// 새로 연 기본 카메라의 줌 범위를 반영. 별도 초광각이 있으면 0.5배까지 넓힌다.
  void _useLensRange(List<CameraDescription> cameras, ZoomRange range) {
    _onUltraWide = false;
    _ultraWide = LensChoice.ultraWide(cameras, _lens, range);
    _zoomRange = _ultraWide == null ? range : range.withUltraWide;
    _zoom = range.clamp(1);
  }

  void _setZoom(double level) {
    final controller = _controller;
    final next = _zoomRange.clamp(level);
    if (controller == null || _switching || (next - _zoom).abs() < 0.01) return;
    setState(() => _zoom = next);
    final wantUltraWide = _ultraWide != null && next < 1;
    unawaited(
      wantUltraWide == _onUltraWide
          ? _applyZoom(controller)
          : _switchUltraWide(controller, wantUltraWide),
    );
  }

  Future<void> _switchUltraWide(CameraController controller, bool use) async {
    final cameras = await ref.read(availableCamerasProvider.future);
    final target = use ? _ultraWide : LensChoice.main(cameras, _lens);
    if (target == null || !mounted) return;
    setState(() => _switching = true);
    await _pauseStream();
    try {
      await controller.setDescription(target);
      _onUltraWide = use;
      await _applyZoom(controller);
    } on CameraException catch (e) {
      debugPrint('[Camera] 초광각 전환 실패: ${e.code}');
      if (mounted) setState(() => _zoom = _onUltraWide ? ZoomRange.appMin : 1);
    } finally {
      if (mounted) setState(() => _switching = false);
      _syncShutterTriggers();
      await _syncPoseStream();
    }
  }

  // ---------------------------------------------------------------------------
  // 자동 촬영·볼륨 버튼
  // ---------------------------------------------------------------------------

  bool get _canShoot =>
      _controller != null && _foreground && !_switching && !_sheetOpen;

  /// 자동 촬영 상태와 볼륨 버튼 구독을 현재 화면 상태에 맞춘다.
  void _syncShutterTriggers() {
    if (!mounted) return;
    _autoShutter.update(
      ready: ref.read(shootSignalProvider) == ShootSignal.ready,
      enabled: ref.read(autoShutterProvider) && _canShoot && !_capturing,
    );
    // 쓰지 않을 때는 구독을 끊어 볼륨 버튼의 원래 기능을 돌려준다.
    if (_canShoot == (_volume != null)) return;
    if (_canShoot) {
      _volume = ref
          .read(volumeButtonProvider)
          .presses
          .listen((_) => unawaited(_capture(AppEvent.volumeCaptured)));
    } else {
      unawaited(_volume?.cancel());
      _volume = null;
    }
  }

  Future<void> _openPresets() async {
    _sheetOpen = true;
    _syncShutterTriggers();
    await showPresetBottomSheet(context);
    _sheetOpen = false;
    _syncShutterTriggers();
  }

  Future<void> _openGallery() {
    _record(AppEvent.galleryOpened);
    return ref.read(captureServiceProvider).openGallery();
  }

  void _record(AppEvent event, {String? preset}) =>
      ref.read(telemetryProvider)?.record(event, preset: preset);

  // ---------------------------------------------------------------------------
  // 실시간 포즈 인식
  // ---------------------------------------------------------------------------

  /// 프리셋이 있고 카메라가 준비됐으면 이미지 스트림을 켜고, 아니면 끈다.
  Future<void> _syncPoseStream() async {
    final controller = _controller;
    final want =
        controller != null &&
        controller.value.isInitialized &&
        _foreground &&
        !_capturing &&
        !_switching &&
        ref.read(activePresetProvider) != null;
    if (want == _streaming || controller == null) return;
    try {
      if (want) {
        await controller.startImageStream(_onCameraImage);
        _streaming = true;
      } else {
        _streaming = false;
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        ref.read(compositionProvider.notifier).clear();
      }
    } on CameraException catch (e) {
      debugPrint('[Pose] 이미지 스트림 전환 실패: ${e.code}');
    }
  }

  Future<void> _pauseStream() async {
    final controller = _controller;
    if (!_streaming || controller == null) return;
    _streaming = false;
    try {
      await controller.stopImageStream();
    } on CameraException catch (e) {
      debugPrint('[Pose] 스트림 중지 실패: ${e.code}');
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    final controller = _controller;
    if (controller == null) return;
    final requested = ref.read(activePresetProvider);
    if (requested == null) return;
    final frame = await _vision.process(
      image,
      controller.description,
      VisionNeeds.of(requested),
    );
    if (!mounted) return;
    final preset = ref.read(activePresetProvider);
    final previewSize = controller.value.previewSize;
    if (frame == null ||
        !mounted ||
        !_streaming ||
        preset == null ||
        previewSize == null ||
        _finderSize.isEmpty) {
      return;
    }
    final targets = Target.of(preset, _finderSize);
    final transform = PreviewTransform(
      screen: _finderSize,
      // previewSize는 센서 기준(가로)이므로 세로 화면 비율은 높이/너비
      previewAspect: previewSize.height / previewSize.width,
      frame: Offset.zero & _finderSize,
    );
    ref
        .read(compositionProvider.notifier)
        .update(
          _people(frame, targets, transform),
          targets,
          focal: _focalLength,
        );
  }

  /// 인식 결과 → 뷰파인더 px 좌표의 사람들
  List<LivePerson> _people(
    VisionFrame frame,
    List<Target> targets,
    PreviewTransform transform,
  ) {
    final people = [
      for (final f in frame.faces)
        LivePerson.face(
          Rect.fromPoints(
            transform.toScreen(f.box.topLeft),
            transform.toScreen(f.box.bottomRight),
          ),
          yawDeg: f.yawDeg,
        ),
    ];
    final landmarks = frame.landmarks;
    final bodyTarget = targets.whereType<BodyTarget>().firstOrNull;
    if (landmarks == null || bodyTarget == null) return people;
    final body = BodyPoints.fromLandmarks([
      for (final l in landmarks)
        () {
          final p = transform.toFrame(Offset(l.x, l.y));
          return PoseLandmark(p.dx, p.dy, l.likelihood);
        }(),
    ], _finderSize);
    return [
      ...people,
      if (body != null) LivePerson.body(body, bodyTarget.span),
    ];
  }

  /// 화면 단위 초점거리: 각도 1°가 화면에서 몇 px인지 정한다.
  double get _focalLength {
    final previewSize = _controller?.value.previewSize;
    var height = _finderSize.height;
    if (previewSize != null) {
      height = PreviewTransform(
        screen: _finderSize,
        previewAspect: previewSize.height / previewSize.width,
        frame: Rect.zero,
      ).previewRect.height;
    }
    return GuideMotion.focalLength(height, _zoom);
  }

  /// 전면/후면 전환. 컨트롤러를 새로 만들지 않고 렌즈만 교체한다
  /// (기존 카메라를 연 채로 새 컨트롤러를 열면 기기에서 무시되는 문제).
  Future<void> _switchLens() async {
    final controller = _controller;
    if (controller == null || _opening != null || _switching) return;
    final target = _lens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final cameras = await ref.read(availableCamerasProvider.future);
    final description = LensChoice.main(cameras, target);
    if (description == null || !mounted) return;

    setState(() => _switching = true);
    await _pauseStream();
    try {
      await controller.setDescription(description);
      _setLens(target);
      final range = await _readZoomRange(controller);
      if (mounted) {
        setState(() => _useLensRange(cameras, range));
      }
      await _applyZoom(controller);
    } on CameraException catch (e) {
      debugPrint('[Camera] 렌즈 교체 실패, 다시 열기: ${e.code}');
      _setLens(target);
      if (mounted) setState(() => _controller = null);
      await controller.dispose();
      await _startCamera();
    } finally {
      if (mounted) setState(() => _switching = false);
      _syncShutterTriggers();
      await _syncPoseStream();
    }
  }

  /// [trigger]는 화면 셔터가 아닌 경우의 촬영 방식 (지표용).
  Future<void> _capture([AppEvent? trigger]) async {
    final controller = _controller;
    if (controller == null ||
        _capturing ||
        _switching ||
        !controller.value.isInitialized) {
      return;
    }
    if (trigger != null) _record(trigger);
    _autoShutter.markShot();
    final ratio = ref.read(viewfinderAspectProvider).ratio;
    setState(() {
      _capturing = true;
      _flash = true;
    });
    unawaited(HapticFeedback.lightImpact());
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _flash = false);
    });

    final messenger = ScaffoldMessenger.of(context);
    // 일부 Android 기기는 이미지 스트림과 촬영을 동시에 못 하므로 잠시 멈춤
    await _pauseStream();
    try {
      final photo = await controller.takePicture();
      final result = await ref
          .read(captureServiceProvider)
          .saveToGallery(await PhotoCropper.crop(photo.path, ratio));
      if (result == SaveResult.saved) {
        unawaited(
          ref.read(saveAdProvider).onSaved(locked: ref.read(guideLockProvider)),
        );
      }
      if (result == SaveResult.saved && mounted) {
        setState(() => _lastPhotoPath = photo.path);
      }
      _record(
        result == SaveResult.saved
            ? AppEvent.photoSaved
            : AppEvent.photoSaveFailed,
        preset: ref.read(selectedPresetProvider)?.id,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            SaveResult.saved => '저장 완료',
            SaveResult.permissionDenied => '설정에서 사진 저장 권한을 허용해 주세요',
            SaveResult.failed => '사진을 저장하지 못했어요',
          }),
          // 잠금 중에는 갤러리로 빠져나가지 않게 한다
          action: result == SaveResult.saved && !ref.read(guideLockProvider)
              ? SnackBarAction(label: '보기', onPressed: _openGallery)
              : null,
          duration: const Duration(seconds: 3),
        ),
      );
    } on CameraException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('촬영에 실패했어요 (${e.code})')));
    } finally {
      if (mounted) setState(() => _capturing = false);
      _syncShutterTriggers();
      await _syncPoseStream();
    }
  }

  void _setLocked(bool locked) {
    final notifier = ref.read(guideLockProvider.notifier);
    locked ? notifier.lock() : notifier.unlock();
    if (!locked) unawaited(ref.read(saveAdProvider).showIfDue());
    // 잠금 중에는 시스템 제스처 바도 숨겨 실수로 앱을 나가지 않게 한다
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        ref.read(guideLockProvider)
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(activePresetProvider);
    final locked = ref.watch(guideLockProvider);
    final aspect = ref.watch(viewfinderAspectProvider);
    final backdrop = ref.watch(cameraBackdropProvider);
    final controller = _controller;
    final hasPreview = controller != null || backdrop != null;
    ref
      ..listen(activePresetProvider, (_, _) => unawaited(_syncPoseStream()))
      ..listen(shootSignalProvider, (_, _) => _syncShutterTriggers())
      ..listen(autoShutterProvider, (_, _) => _syncShutterTriggers());

    final padding = MediaQuery.viewPaddingOf(context);
    final finder = aspect.layout(
      MediaQuery.sizeOf(context),
      safeTop: padding.top,
      top: padding.top + _topBarHeight,
      bottom: padding.bottom + _bottomPanelHeight,
    );
    _finderSize = finder.size;

    return PopScope(
      // 잠금 중 뒤로 가기로 앱이 닫히지 않게 한다
      canPop: !locked,
      child: Scaffold(
        backgroundColor: AppTheme.ink,
        body: Stack(
          children: [
            Positioned.fromRect(
              rect: finder,
              child: _Viewfinder(
                preview:
                    backdrop ??
                    (controller != null
                        ? GestureDetector(
                            // 두 손가락 핀치 줌 (잠금 중에는 버튼으로만)
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: (_) => _pinchStartZoom = _zoom,
                            onScaleUpdate: (d) {
                              if (!locked && d.pointerCount >= 2) {
                                _setZoom(_pinchStartZoom * d.scale);
                              }
                            },
                            child: CameraPreviewFullscreen(
                              controller: controller,
                            ),
                          )
                        : _CameraFallback(
                            issue: _issue,
                            onRetry: _startCamera,
                          )),
                preset: preset,
                focal: _focalLength,
                flash: _flash,
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  if (locked)
                    const _LockedHint()
                  else ...[
                    _SettingsBar(onLock: () => _setLocked(true)),
                    if (preset != null) _GuidePanelLayer(preset: preset),
                  ],
                  const Spacer(),
                  _CoachLayer(preset: preset),
                  const SizedBox(height: 12),
                  if (hasPreview)
                    ZoomSelector(
                      // 스크린샷 모드는 일반 휴대폰과 같은 0.5~3배 표시
                      range: backdrop != null
                          ? const ZoomRange(0.5, 3)
                          : _zoomRange,
                      zoom: _zoom,
                      onSelected: _setZoom,
                      maxStop: locked ? 2 : ZoomRange.appMax,
                    ),
                  const SizedBox(height: 14),
                  _BottomControls(
                    locked: locked,
                    onUnlock: () => _setLocked(false),
                    lastPhotoPath: _lastPhotoPath,
                    onGalleryTap: _openGallery,
                    preset: preset,
                    capturing: _capturing,
                    counting: _autoShutter.counting,
                    countDuration: _autoShutter.hold,
                    onPresetTap: _openPresets,
                    onShutter: backdrop != null
                        ? () {}
                        : controller == null || _switching
                        ? null
                        : _capture,
                    onSwitchLens: _hasBothLenses && !_capturing && !_switching
                        ? _switchLens
                        : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 뷰파인더 배치에 쓰는 위·아래 컨트롤 높이
  static const _topBarHeight = 60.0;
  static const _bottomPanelHeight = 218.0;

  bool get _hasBothLenses {
    final cameras = ref.watch(availableCamerasProvider).value ?? const [];
    bool has(CameraLensDirection d) => cameras.any((c) => c.lensDirection == d);
    return has(CameraLensDirection.back) && has(CameraLensDirection.front);
  }
}

/// 뷰파인더: 프리뷰 + 격자·프레임 + 가이드 + 기울기 인디케이터.
/// 좌표는 모두 이 위젯 크기 기준이라 화면 비율이 바뀌면 함께 다시 계산된다.
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.preview,
    required this.preset,
    required this.focal,
    required this.flash,
  });

  final Widget preview;
  final Preset? preset;
  final double focal;
  final bool flash;

  @override
  Widget build(BuildContext context) {
    final preset = this.preset;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          children: [
            Positioned.fill(child: preview),
            if (preset != null) ...[
              const Positioned.fill(child: _FrameCornersLayer()),
              if (!preset.isTemplate)
                Positioned.fill(
                  child: _GhostLayer(preset: preset, focal: focal),
                ),
              Positioned.fill(
                child: _DynamicFrameLayer(
                  preset: preset,
                  finder: constraints.biggest,
                ),
              ),
            ],
            Center(child: _AngleIndicatorLayer(focal: focal)),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: flash ? 0.7 : 0,
                  child: const ColoredBox(color: AppTheme.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 잠금 중 안내: 촬영자가 할 일만 짧게.
class _LockedHint extends StatelessWidget {
  const _LockedHint();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppTheme.scrim,
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text('아래 안내대로 움직이고, 초록불에 찍으세요'),
  );
}

/// 설정 줄: 화면 비율 · 좌우 반전 · 자동 촬영 · 가이드 잠금
class _SettingsBar extends ConsumerWidget {
  const _SettingsBar({required this.onLock});

  final VoidCallback onLock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPreset = ref.watch(selectedPresetProvider) != null;
    final mirrored = ref.watch(guideMirrorProvider);
    final auto = ref.watch(autoShutterProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
      child: Row(
        children: [
          // 큰 글자에서도 넘치지 않게 줄여서 표시
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  _SettingChip(
                    label: ref.watch(viewfinderAspectProvider).label,
                    semantics: '화면 비율',
                    icon: Icons.aspect_ratio,
                    onTap: ref.read(viewfinderAspectProvider.notifier).cycle,
                  ),
                  const SizedBox(width: 8),
                  _SettingChip(
                    label: '반전',
                    semantics: '가이드 좌우 반전',
                    icon: Icons.flip,
                    active: mirrored,
                    onTap: hasPreset
                        ? ref.read(guideMirrorProvider.notifier).toggle
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _SettingChip(
                    label: '자동',
                    semantics: '자동 촬영',
                    icon: Icons.timer_outlined,
                    active: auto,
                    onTap: ref.read(autoShutterProvider.notifier).toggle,
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '앱 정보',
            onPressed: () => showAboutSheet(context),
            icon: const Icon(Icons.info_outline),
          ),
          LockButton(
            locked: false,
            onLock: hasPreset ? onLock : null,
            onUnlock: () {},
          ),
        ],
      ),
    );
  }
}

class _SettingChip extends StatelessWidget {
  const _SettingChip({
    required this.label,
    required this.semantics,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final String semantics;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppTheme.ink : AppTheme.white;
    return Semantics(
      button: true,
      toggled: active,
      label: semantics,
      value: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: active ? AppTheme.coral : AppTheme.scrim,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 뷰파인더 모서리. 촬영 순간에는 사라진다.
class _FrameCornersLayer extends ConsumerWidget {
  const _FrameCornersLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(
      shootSignalProvider.select((s) => s == ShootSignal.ready),
    );
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: ready ? 0 : 1,
        duration: const Duration(milliseconds: 250),
        child: LayoutBuilder(
          builder: (context, c) => CustomPaint(
            size: Size.infinite,
            painter: FrameGuidePainter(
              aspectRatio: c.biggest.aspectRatio,
              showGrid: false,
            ),
          ),
        ),
      ),
    );
  }
}

/// 자세계는 센서 주기로 다시 그려지므로 분리. 폰 각도가 문제일 때만 보인다.
class _AngleIndicatorLayer extends ConsumerWidget {
  const _AngleIndicatorLayer({required this.focal});

  final double focal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(angleGuideProvider);
    if (guide == null) return const SizedBox.shrink();
    // 사람을 맞추는 중에는 방해하지 않는다
    final busy = ref.watch(
      compositionProvider.select((s) => (s?.hasPerson ?? false) && !s!.fits),
    );
    return AnimatedOpacity(
      opacity: guide.state == AngleState.off && !busy ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: AngleIndicator(guide: guide, focal: focal),
    );
  }
}

/// 하단 코칭 문구. 센서·포즈 주기로 갱신되므로 분리.
class _CoachLayer extends ConsumerWidget {
  const _CoachLayer({required this.preset});

  final Preset? preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = this.preset;
    return CoachPill(
      message: CoachMessage.of(
        angle: ref.watch(angleGuideProvider),
        fit: preset == null
            ? null
            : ref.watch(compositionProvider)?.fit ?? CompositionFit.none,
        ready: ref.watch(shootSignalProvider) == ShootSignal.ready,
      ),
    );
  }
}

class _GhostLayer extends ConsumerWidget {
  const _GhostLayer({required this.preset, required this.focal});

  final Preset preset;
  final double focal;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ReferenceOverlay(
    preset: preset,
    opacity: ref.watch(overlayOpacityProvider),
    visible: ref.watch(ghostVisibleProvider),
    motion: ref.watch(guideMotionProvider),
    focal: focal,
  );
}

class _DynamicFrameLayer extends ConsumerWidget {
  const _DynamicFrameLayer({required this.preset, required this.finder});

  final Preset preset;
  final Size finder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(compositionProvider);
    final targets = Target.of(preset, finder);
    // 화면 비율·반전이 방금 바뀌었으면 새 자리로
    final current =
        state != null &&
        state.targets.length == targets.length &&
        targets.isNotEmpty &&
        state.targets.first.center == targets.first.center;
    return DynamicFrame(
      template: preset.template,
      silhouetteOpacity: preset.isTemplate
          ? ref.watch(overlayOpacityProvider)
          : 0,
      signal: ref.watch(shootSignalProvider) ?? ShootSignal.waiting,
      state: current
          ? state
          : CompositionState(targets: targets, fit: CompositionFit.none),
    );
  }
}

/// 실루엣 투명도 + 촬영 팁 + 예시 사진.
/// 투명도는 항상 조절할 수 있고, 팁·예시는 사람이 잡히면 구도를 가리지 않도록 사라진다.
class _GuidePanelLayer extends ConsumerWidget {
  const _GuidePanelLayer({required this.preset});

  final Preset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTips = ref.watch(ghostVisibleProvider);
    Widget fade(Widget child) => IgnorePointer(
      ignoring: !showTips,
      child: AnimatedOpacity(
        opacity: showTips ? 1 : 0,
        duration: const Duration(milliseconds: 300),
        child: child,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                OpacitySlider(
                  label: preset.isTemplate ? '실루엣' : '사진',
                  value: ref.watch(overlayOpacityProvider),
                  onChanged: ref.read(overlayOpacityProvider.notifier).set,
                ),
                const SizedBox(height: 8),
                fade(GuideCard(preset: preset)),
              ],
            ),
          ),
          if (preset.hasPhoto) ...[
            const SizedBox(width: 10),
            fade(ReferencePip(preset: preset)),
          ],
        ],
      ),
    );
  }
}

class _BottomControls extends ConsumerWidget {
  const _BottomControls({
    required this.locked,
    required this.onUnlock,
    required this.lastPhotoPath,
    required this.onGalleryTap,
    required this.preset,
    required this.capturing,
    required this.counting,
    required this.countDuration,
    required this.onPresetTap,
    required this.onShutter,
    required this.onSwitchLens,
  });

  final bool locked;
  final VoidCallback onUnlock;
  final String? lastPhotoPath;
  final VoidCallback onGalleryTap;
  final Preset? preset;
  final bool capturing;
  final ValueListenable<bool> counting;
  final Duration countDuration;
  final VoidCallback onPresetTap;
  final VoidCallback? onShutter;
  final VoidCallback? onSwitchLens;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(shootSignalProvider) == ShootSignal.ready;
    // 셔터는 항상 가운데: 왼쪽과 오른쪽을 같은 폭으로
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: SizedBox(
        height: 88,
        child: Row(
          children: [
            Expanded(
              child: locked
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        GalleryButton(
                          lastPhotoPath: lastPhotoPath,
                          onTap: onGalleryTap,
                        ),
                        _PresetThumbButton(preset: preset, onTap: onPresetTap),
                      ],
                    ),
            ),
            ValueListenableBuilder(
              valueListenable: counting,
              builder: (_, counting, _) => ShutterButton(
                onPressed: onShutter,
                busy: capturing,
                ready: ready,
                counting: counting,
                countDuration: countDuration,
              ),
            ),
            Expanded(
              child: Center(
                child: locked
                    ? LockButton(locked: true, onLock: null, onUnlock: onUnlock)
                    : _RoundIconButton(
                        icon: Icons.cameraswitch_outlined,
                        tooltip: '렌즈 전환',
                        onPressed: onSwitchLens,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetThumbButton extends StatelessWidget {
  const _PresetThumbButton({required this.preset, required this.onTap});

  final Preset? preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preset = this.preset;
    return Tooltip(
      message: '구도 프리셋',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 56,
          height: 56,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppTheme.scrim,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: preset != null ? AppTheme.coral : AppTheme.whiteMuted,
              width: 2,
            ),
          ),
          child: preset == null
              ? const Icon(Icons.grid_view_rounded)
              : ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: preset.isTemplate
                      ? CompositionDiagram(preset: preset)
                      : ReferenceImage(preset: preset),
                ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      iconSize: 26,
      style: IconButton.styleFrom(
        backgroundColor: AppTheme.scrim,
        foregroundColor: AppTheme.white,
        disabledBackgroundColor: AppTheme.scrimSoft,
        fixedSize: const Size(56, 56),
      ),
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback({required this.issue, required this.onRetry});

  final _CameraIssue issue;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final (message, canRetry) = switch (issue) {
      _CameraIssue.none => ('', false),
      _CameraIssue.unavailable => ('이 기기에서는 카메라를 사용할 수 없어요', false),
      _CameraIssue.permissionDenied => (
        '카메라 권한이 필요해요\n설정에서 라익찍스의 카메라를 허용해 주세요',
        true,
      ),
      _CameraIssue.failed => ('카메라를 여는 중 문제가 생겼어요', true),
    };
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppTheme.inkRaised, AppTheme.ink],
        ),
      ),
      child: Center(
        child: issue == _CameraIssue.none
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message, textAlign: TextAlign.center),
                  if (canRetry) ...[
                    const SizedBox(height: 12),
                    if (issue == _CameraIssue.permissionDenied)
                      FilledButton(
                        onPressed: AppSettings.openAppSettings,
                        child: const Text('설정 열기'),
                      )
                    else
                      OutlinedButton(
                        onPressed: onRetry,
                        child: const Text('다시 시도'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
