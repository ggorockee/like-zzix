import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/ad_providers.dart';
import '../widgets/logo_mark.dart';

/// 로딩 화면: 네이티브 스플래시와 같은 배경·로고 위치에서 이어받아 로고가 통통 튄다.
/// 앱 초기화가 끝나고 최소 표시 시간이 지나면 카메라 화면으로 이동.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// 애니메이션이 한두 번은 보이도록 하는 최소 표시 시간
  static const minimumDuration = Duration(milliseconds: 1600);

  /// 초기화가 느려도(오프라인 등) 이 시간 뒤에는 넘어간다. 초기화는 뒤에서 계속됨.
  static const maximumWait = Duration(seconds: 4);

  /// 네이티브 스플래시 이미지(768px @4x)와 같은 크기
  static const logoSize = 192.0;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat();

  @override
  void initState() {
    super.initState();
    unawaited(_proceed());
  }

  Future<void> _proceed() async {
    await Future.wait([
      Future<void>.delayed(SplashScreen.minimumDuration),
      ref
          .read(appInitProvider.future)
          .timeout(
            SplashScreen.maximumWait,
            onTimeout: () => throw TimeoutException(null),
          )
          .then<void>(
            (_) {},
            onError: (Object e) => debugPrint('[Splash] 초기화 대기 종료: $e'),
          ),
    ]);
    if (mounted) context.go('/');
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LogoMarkPainter.splashColor,
      body: Stack(
        children: [
          Center(child: BouncingLogo(animation: _bounce)),
          Align(
            alignment: const Alignment(0, 0.42),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 600),
              builder: (context, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - t)),
                  child: child,
                ),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '라익찍스',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '딱 이대로 찍어주는 완벽 구도 카메라',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 바닥에 닿을 때 찌그러지고(squash) 올라갈 때 늘어나는(stretch) 통통 튀는 로고.
class BouncingLogo extends StatelessWidget {
  const BouncingLogo({
    super.key,
    required this.animation,
    this.size = SplashScreen.logoSize,
    this.jumpHeight = 70,
  });

  final Animation<double> animation;
  final double size;
  final double jumpHeight;

  /// t(0~1) → 높이(0~1). 포물선이라 꼭대기에서 느려지고 바닥에서 빨라짐.
  static double heightAt(double t) => 1 - math.pow(2 * t - 1, 2).toDouble();

  /// 바닥 근처에서 찌그러짐 정도 (0~1)
  static double squashAt(double t) {
    final h = heightAt(t);
    return h < 0.15 ? (0.15 - h) / 0.15 : 0;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        final h = heightAt(t);
        final squash = squashAt(t);
        final stretch = h > 0.15 && h < 0.7 ? 0.05 : 0.0;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // 그림자: 높이 올라갈수록 작고 옅게
              Positioned(
                bottom: size * 0.12 - 10,
                child: Container(
                  width: size * 0.55 * (1 - 0.45 * h),
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18 * (1 - 0.6 * h)),
                    borderRadius: const BorderRadius.all(
                      Radius.elliptical(100, 12),
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -jumpHeight * h),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.diagonal3Values(
                    1 + 0.14 * squash - stretch,
                    1 - 0.18 * squash + stretch,
                    1,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        );
      },
      child: const LogoMark(
        size: SplashScreen.logoSize,
        background: LogoBackground.none,
      ),
    );
  }
}
