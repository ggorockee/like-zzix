import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/app_theme.dart';
import '../models/preset.dart';
import '../providers/camera_providers.dart';
import '../providers/preset_providers.dart';
import '../services/capture_service.dart';
import '../providers/attitude_providers.dart';
import '../widgets/angle_indicator.dart';
import '../widgets/camera_preview_fullscreen.dart';
import '../widgets/frame_guide.dart';
import '../widgets/guide_card.dart';
import '../widgets/reference_image.dart';
import '../widgets/reference_pip.dart';
import '../widgets/opacity_slider.dart';
import '../widgets/preset_bottom_sheet.dart';
import '../widgets/shutter_button.dart';
import '../widgets/silhouette_painter.dart';

/// 메인 카메라 화면 (PRD Step 2): 풀스크린 프리뷰 + 실루엣 오버레이 + 촬영 컨트롤.
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
      return;
    }
    if (cameras.isEmpty) {
      if (mounted) setState(() => _issue = _CameraIssue.unavailable);
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
      return;
    }
    // 초기화 중 화면을 떠났으면 닫는다 (resumed에서 다시 연다).
    if (!mounted || !_foreground) {
      debugPrint('[Camera] 초기화 완료 시점에 비활성 → 닫음');
      await controller.dispose();
      return;
    }
    final old = _controller;
    setState(() {
      _controller = controller;
      _lens = description.lensDirection;
      _issue = _CameraIssue.none;
    });
    await old?.dispose();
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
    try {
      await controller.setDescription(description);
      _lens = target;
    } on CameraException catch (e) {
      debugPrint('[Camera] 렌즈 교체 실패, 다시 열기: ${e.code}');
      _lens = target;
      if (mounted) setState(() => _controller = null);
      await controller.dispose();
      await _startCamera();
    } finally {
      if (mounted) setState(() => _switching = false);
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
    try {
      final photo = await controller.takePicture();
      final result = await ref
          .read(captureServiceProvider)
          .saveToGallery(photo.path);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            SaveResult.saved => '저장 완료',
            SaveResult.permissionDenied => '사진 저장 권한을 허용해 주세요',
            SaveResult.failed => '사진을 저장하지 못했어요',
          }),
          duration: const Duration(seconds: 2),
        ),
      );
    } on CameraException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('촬영에 실패했어요 (${e.code})')));
    } finally {
      if (mounted) setState(() => _capturing = false);
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: controller != null
                ? CameraPreviewFullscreen(controller: controller)
                : _CameraFallback(issue: _issue, onRetry: _startCamera),
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
              child: IgnorePointer(
                child: Opacity(
                  opacity: opacity,
                  child: CustomPaint(
                    painter: SilhouettePainter(
                      preset: preset,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
          const Center(child: _AngleIndicatorLayer()),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: _flash ? 0.7 : 0,
                child: const ColoredBox(color: Colors.white),
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
                _AngleStatusLayer(hasPreset: preset != null),
                const SizedBox(height: 16),
                _BottomControls(
                  preset: preset,
                  capturing: _capturing,
                  onPresetTap: () => showPresetBottomSheet(context),
                  onShutter: controller == null || _switching ? null : _capture,
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
  const _AngleIndicatorLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(angleGuideProvider);
    return guide == null
        ? const SizedBox.shrink()
        : AngleIndicator(guide: guide);
  }
}

class _AngleStatusLayer extends ConsumerWidget {
  const _AngleStatusLayer({required this.hasPreset});

  final bool hasPreset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guide = ref.watch(angleGuideProvider);
    return guide == null
        ? const SizedBox(height: 36)
        : AngleStatus(guide: guide, hasPreset: hasPreset);
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
    required this.preset,
    required this.capturing,
    required this.onPresetTap,
    required this.onShutter,
    required this.onSwitchLens,
  });

  final Preset? preset;
  final bool capturing;
  final VoidCallback onPresetTap;
  final VoidCallback? onShutter;
  final VoidCallback? onSwitchLens;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PresetThumbButton(preset: preset, onTap: onPresetTap),
          ShutterButton(onPressed: onShutter, busy: capturing),
          _RoundIconButton(
            icon: Icons.cameraswitch_outlined,
            tooltip: '렌즈 전환',
            onPressed: onSwitchLens,
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
            color: Colors.black45,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: preset != null ? AppTheme.brand : Colors.white70,
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
        backgroundColor: Colors.black45,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Colors.black26,
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
          colors: [Color(0xFF1C1C1E), Colors.black],
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
