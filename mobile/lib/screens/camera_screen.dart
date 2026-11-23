import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../models/guide_motion.dart';
import '../models/preset.dart';
import '../providers/camera_providers.dart';
import '../providers/preset_providers.dart';
import '../services/capture_service.dart';
import '../models/preview_transform.dart';
import '../models/zoom_range.dart';
import '../providers/api_providers.dart';
import '../providers/attitude_providers.dart';
import '../providers/guide_motion_provider.dart';
import '../providers/pose_providers.dart';
import '../services/pose_service.dart';
import '../services/telemetry_service.dart';
import '../widgets/angle_indicator.dart';
import '../widgets/camera_preview_fullscreen.dart';
import '../widgets/frame_guide.dart';
import '../widgets/gallery_button.dart';
import '../widgets/guide_card.dart';
import '../widgets/guide_status.dart';
import '../widgets/opacity_slider.dart';
import '../widgets/preset_bottom_sheet.dart';
import '../widgets/reference_image.dart';
import '../widgets/reference_overlay.dart';
import '../widgets/reference_pip.dart';
import '../widgets/shutter_button.dart';
import '../widgets/silhouette_painter.dart';
import '../widgets/zoom_selector.dart';

/// 메인 카메라 화면: 풀스크린 프리뷰 + 레퍼런스 오버레이 + 실시간 구도 판정 + 촬영 컨트롤.
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

  /// 앱이 포그라운드인지. 권한 팝업 등으로 inactive일 때 열린 카메라는 바로 닫는다.
  bool _foreground = true;

  /// 진행 중인 카메라 열기 작업 (동시에 두 번 열지 않도록 직렬화).
  Future<void>? _opening;

  /// 실시간 포즈 인식 (프리셋을 골랐을 때만 이미지 스트림 실행)
  final _pose = PoseService();
  bool _streaming = false;

  /// 프레임 좌표 변환에 쓰는 마지막 화면 크기
  Size _screenSize = Size.zero;

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
    unawaited(_pose.close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[Camera] lifecycle: $state');
    switch (state) {
      case AppLifecycleState.inactive || AppLifecycleState.paused:
        // 백그라운드/권한 팝업: 카메라를 놓아준다.
        _foreground = false;
        final controller = _controller;
        if (controller == null) return;
        _streaming = false;
        setState(() => _controller = null);
        unawaited(controller.dispose());
      case AppLifecycleState.resumed:
        _foreground = true;
        if (_controller == null) unawaited(_startCamera());
      case AppLifecycleState.detached || AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _startCamera() =>
      _opening ??= _openCamera().whenComplete(() => _opening = null);

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
    final description = cameras.firstWhere(
      (c) => c.lensDirection == _lens,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: PoseService.imageFormatGroup,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      if (!mounted) return;
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
      _zoomRange = zoomRange;
      _zoom = zoomRange.clamp(1);
    });
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
      await controller.setZoomLevel(_zoom);
    } on CameraException catch (e) {
      debugPrint('[Camera] 줌 설정 실패: ${e.code}');
    }
  }

  void _setZoom(double level) {
    final controller = _controller;
    final next = _zoomRange.clamp(level);
    if (controller == null || (next - _zoom).abs() < 0.01) return;
    setState(() => _zoom = next);
    unawaited(_applyZoom(controller));
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
        ref.read(selectedPresetProvider) != null;
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
        ref.read(poseMatchProvider.notifier).clear();
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
    final frame = await _pose.process(image, controller.description);
    final preset = ref.read(selectedPresetProvider);
    final previewSize = controller.value.previewSize;
    if (frame == null ||
        !mounted ||
        !_streaming ||
        preset == null ||
        previewSize == null ||
        _screenSize.isEmpty) {
      return;
    }
    final frameRect = SilhouettePainter.frameRect(
      _screenSize,
      preset.aspectRatio,
    );
    final transform = PreviewTransform(
      screen: _screenSize,
      // previewSize는 센서 기준(가로)이므로 세로 화면 비율은 높이/너비
      previewAspect: previewSize.height / previewSize.width,
      frame: frameRect,
    );
    final live = frame.landmarks == null
        ? null
        : [
            for (final l in frame.landmarks!)
              () {
                final f = transform.toFrame(Offset(l.x, l.y));
                return PoseLandmark(f.dx, f.dy, l.likelihood);
              }(),
          ];
    // 화면에 보이는 가이드와 같은 위치를 기준으로 판정한다.
    final motion = ref.read(guideMotionProvider);
    ref
        .read(poseMatchProvider.notifier)
        .update(
          live,
          reference: motion.locked
              ? null
              : motion.displace(
                  preset.landmarks,
                  screen: _screenSize,
                  frame: frameRect,
                  focal: _focalLength,
                ),
        );
  }

  /// 화면 단위 초점거리: 각도 1°가 화면에서 몇 px인지 정한다.
  double get _focalLength {
    final previewSize = _controller?.value.previewSize;
    var height = _screenSize.height;
    if (previewSize != null) {
      height = PreviewTransform(
        screen: _screenSize,
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
    final description = cameras
        .where((c) => c.lensDirection == target)
        .firstOrNull;
    if (description == null || !mounted) return;

    setState(() => _switching = true);
    await _pauseStream();
    try {
      await controller.setDescription(description);
      _setLens(target);
      final range = await _readZoomRange(controller);
      if (mounted) {
        setState(() {
          _zoomRange = range;
          _zoom = range.clamp(1);
        });
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
      await _syncPoseStream();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing || !controller.value.isInitialized) {
      return;
    }
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
          .saveToGallery(photo.path);
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
            SaveResult.permissionDenied => '사진 저장 권한을 허용해 주세요',
            SaveResult.failed => '사진을 저장하지 못했어요',
          }),
          action: result == SaveResult.saved
              ? SnackBarAction(label: '보기', onPressed: _openGallery)
              : null,
          duration: const Duration(seconds: 3),
        ),
      );
    } on CameraException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('촬영에 실패했어요 (${e.code})')));
    } finally {
      if (mounted) setState(() => _capturing = false);
      await _syncPoseStream();
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = ref.watch(selectedPresetProvider);
    final opacity = ref.watch(overlayOpacityProvider);
    final cameras = ref.watch(availableCamerasProvider).value ?? const [];
    final hasBothLenses =
        cameras.any((c) => c.lensDirection == CameraLensDirection.back) &&
        cameras.any((c) => c.lensDirection == CameraLensDirection.front);
    final controller = _controller;
    final backdrop = ref.watch(cameraBackdropProvider);
    _screenSize = MediaQuery.sizeOf(context);
    ref.listen(selectedPresetProvider, (_, _) => unawaited(_syncPoseStream()));

    return Scaffold(
      backgroundColor: AppTheme.ink,
      body: Stack(
        children: [
          Positioned.fill(
            child:
                backdrop ??
                (controller != null
                    ? GestureDetector(
                        // 두 손가락 핀치 줌
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (_) => _pinchStartZoom = _zoom,
                        onScaleUpdate: (d) {
                          if (d.pointerCount >= 2) {
                            _setZoom(_pinchStartZoom * d.scale);
                          }
                        },
                        child: CameraPreviewFullscreen(controller: controller),
                      )
                    : _CameraFallback(issue: _issue, onRetry: _startCamera)),
          ),
          if (preset != null) ...[
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: FrameGuidePainter(aspectRatio: preset.aspectRatio),
                ),
              ),
            ),
            Positioned.fill(
              child: _ReferenceOverlayLayer(
                preset: preset,
                opacity: opacity,
                focal: _focalLength,
              ),
            ),
          ],
          Center(child: _AngleIndicatorLayer(focal: _focalLength)),
          const Align(
            alignment: Alignment(0, -0.2),
            child: _PerfectBannerLayer(),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _flash ? 0.7 : 0,
                child: const ColoredBox(color: AppTheme.white),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                if (preset != null)
                  _TopPanel(
                    preset: preset,
                    opacity: opacity,
                    onOpacityChanged: ref
                        .read(overlayOpacityProvider.notifier)
                        .set,
                  ),
                const Spacer(),
                _GuideStatusLayer(hasPreset: preset != null),
                const SizedBox(height: 12),
                if (controller != null || backdrop != null)
                  ZoomSelector(
                    // 스크린샷 모드는 일반 휴대폰과 같은 0.5~3배 표시
                    range: backdrop != null
                        ? const ZoomRange(0.5, 3)
                        : _zoomRange,
                    zoom: _zoom,
                    onSelected: _setZoom,
                  ),
                const SizedBox(height: 14),
                _BottomControls(
                  lastPhotoPath: _lastPhotoPath,
                  onGalleryTap: _openGallery,
                  preset: preset,
                  capturing: _capturing,
                  onPresetTap: () => showPresetBottomSheet(context),
                  onShutter: backdrop != null
                      ? () {}
                      : controller == null || _switching
                      ? null
                      : _capture,
                  onSwitchLens: hasBothLenses && !_capturing && !_switching
                      ? _switchLens
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 자세계는 센서 주기로 다시 그려지므로 카메라 화면 전체와 분리.
class _AngleIndicatorLayer extends ConsumerWidget {
  const _AngleIndicatorLayer({required this.focal});

  final double focal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(angleGuideProvider);
    return guide == null
        ? const SizedBox.shrink()
        : AngleIndicator(guide: guide, focal: focal);
  }
}

/// 하단 안내 문구 (각도 + 구도). 센서·포즈 주기로 갱신되므로 분리.
class _GuideStatusLayer extends ConsumerWidget {
  const _GuideStatusLayer({required this.hasPreset});

  final bool hasPreset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GuideStatus(
      angle: ref.watch(angleGuideProvider),
      pose: ref.watch(poseMatchProvider),
      hasPreset: hasPreset,
    );
  }
}

class _PerfectBannerLayer extends ConsumerWidget {
  const _PerfectBannerLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfect = ref.watch(
      poseMatchProvider.select((s) => s?.perfect ?? false),
    );
    return PerfectMatchBanner(visible: perfect);
  }
}

class _ReferenceOverlayLayer extends ConsumerWidget {
  const _ReferenceOverlayLayer({
    required this.preset,
    required this.opacity,
    required this.focal,
  });

  final Preset preset;
  final double opacity;
  final double focal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final match = ref.watch(poseMatchProvider);
    return ReferenceOverlay(
      preset: preset,
      opacity: opacity,
      match: match?.result,
      live: match?.live,
      perfect: match?.perfect ?? false,
      motion: ref.watch(guideMotionProvider),
      focal: focal,
    );
  }
}

class _TopPanel extends StatelessWidget {
  const _TopPanel({
    required this.preset,
    required this.opacity,
    required this.onOpacityChanged,
  });

  final Preset preset;
  final double opacity;
  final ValueChanged<double> onOpacityChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                OpacitySlider(value: opacity, onChanged: onOpacityChanged),
                const SizedBox(height: 8),
                GuideCard(preset: preset),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ReferencePip(preset: preset),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.lastPhotoPath,
    required this.onGalleryTap,
    required this.preset,
    required this.capturing,
    required this.onPresetTap,
    required this.onShutter,
    required this.onSwitchLens,
  });

  final String? lastPhotoPath;
  final VoidCallback onGalleryTap;
  final Preset? preset;
  final bool capturing;
  final VoidCallback onPresetTap;
  final VoidCallback? onShutter;
  final VoidCallback? onSwitchLens;

  @override
  Widget build(BuildContext context) {
    // 셔터는 항상 가운데: 왼쪽(갤러리·프리셋)과 오른쪽(렌즈)을 같은 폭으로
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      child: Row(
        children: [
          Expanded(
            child: Row(
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
          ShutterButton(onPressed: onShutter, busy: capturing),
          Expanded(
            child: Center(
              child: _RoundIconButton(
                icon: Icons.cameraswitch_outlined,
                tooltip: '렌즈 전환',
                onPressed: onSwitchLens,
              ),
            ),
          ),
        ],
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
                  child: ReferenceImage(preset: preset, silhouetteStroke: 1),
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
        '카메라 권한이 필요해요\n설정 > 애플리케이션 > 라익찍스에서 허용해 주세요',
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
