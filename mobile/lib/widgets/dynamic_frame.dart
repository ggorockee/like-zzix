import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/app_theme.dart';
import '../models/composition.dart';
import '../models/composition_fit.dart';
import '../models/subject.dart';
import '../providers/composition_providers.dart';
import '../providers/shooting_providers.dart';
import 'composition_painter.dart';
import 'guide_stroke.dart';

/// 살아 있는 구도 가이드: 구도선 + 인물 자리 + 사람을 따라다니는 프레임.
///
/// - 조건이 맞은 부분(위치 점·발끝선·시선 화살표)만 초록으로 반응
/// - 사람 프레임은 구도가 가까워질수록 자리에 자석처럼 붙음
/// - 완성되면 전체가 초록 → 0.3초 뒤 은은하게 투명해지고 얇은 테두리만 남음
class DynamicFrame extends StatefulWidget {
  const DynamicFrame({
    super.key,
    required this.state,
    required this.signal,
    this.template,
    this.opacity = 1,
  });

  final CompositionState? state;
  final ShootSignal signal;
  final CompositionTemplate? template;

  /// 구도선 투명도 (사용자 설정)
  final double opacity;

  @override
  State<DynamicFrame> createState() => _DynamicFrameState();
}

class _DynamicFrameState extends State<DynamicFrame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _visual = ValueNotifier(const FrameVisual());
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _visual.dispose();
    super.dispose();
  }

  /// 인식(초당 10~15회)보다 부드럽게, 매 프레임 목표 값으로 다가간다.
  void _onTick(Duration elapsed) {
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    final next = _visual.value.step(widget.state, widget.signal, dt);
    // 움직이는 것이 없으면 다시 그리지 않는다 (발열)
    if (next.isIdleAfter(_visual.value)) return;
    _visual.value = next;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _DynamicFramePainter(
          visual: _visual,
          targets: widget.state?.targets ?? const [],
          action: widget.state?.fit.action ?? CoachAction.findPerson,
          template: widget.template,
          opacity: widget.opacity,
        ),
      ),
    ),
  );
}

/// 사람 한 명의 화면 표시 값.
@immutable
class PersonVisual {
  const PersonVisual({this.box, this.presence = 0, this.parts = const {}});

  /// 부드럽게 움직이는 프레임 (자석 효과 적용)
  final Rect? box;

  /// 프레임 투명도 0~1
  final double presence;

  /// 조건별 초록 전환 0~1
  final Map<GuidePart, double> parts;

  double part(GuidePart p) => parts[p] ?? 0;
}

/// 화면에 그려지는 중간 값.
@immutable
class FrameVisual {
  const FrameVisual({
    this.people = const [],
    this.ready = 0,
    this.readySeconds = 0,
    this.fade = 1,
    this.warn = 0,
    this.phase = 0,
  });

  final List<PersonVisual> people;

  /// 초록 전환 0~1
  final double ready;

  /// 초록이 된 뒤 지난 시간(초)
  final double readySeconds;

  /// 가이드 진하기 1 → [faded]
  final double fade;

  /// 노랑(각도 이탈) 전환 0~1
  final double warn;

  /// 화살표 애니메이션 위상 0~1
  final double phase;

  /// 초록이 된 뒤 투명해지기 시작할 때까지
  static const fadeDelay = 0.3;

  /// 투명해졌을 때 남는 진하기
  static const faded = 0.1;

  /// 이 점수부터 자석이 붙기 시작해 90점에서 완전히 붙는다
  static const _snapFrom = 55.0;

  static double snapOf(double score) {
    final t = ((score - _snapFrom) / (CompositionFit.enterScore - _snapFrom))
        .clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  FrameVisual step(CompositionState? state, ShootSignal signal, double dt) {
    double toward(double from, double to, double tau) =>
        from + (to - from) * (1 - math.exp(-dt / tau));
    final isReady = signal == ShootSignal.ready;
    final seconds = isReady ? readySeconds + dt : 0.0;
    final fading = isReady && seconds > fadeDelay;

    return FrameVisual(
      people: [
        for (final (i, target) in (state?.targets ?? const <Target>[]).indexed)
          _person(
            i < people.length ? people[i] : const PersonVisual(),
            target,
            i < state!.fit.targets.length ? state.fit.targets[i] : null,
            toward,
            dt,
          ),
      ],
      ready: toward(ready, isReady ? 1 : 0, 0.08),
      readySeconds: seconds,
      // 사라질 때는 은은하게, 어긋나면 바로 다시 나타난다
      fade: toward(fade, fading ? faded : 1, fading ? 0.18 : 0.08),
      warn: toward(warn, signal == ShootSignal.angleOff ? 1 : 0, 0.1),
      phase: (phase + dt / 0.9) % 1,
    );
  }

  /// 사람도 없고 전환도 끝나 화면이 그대로인지.
  bool isIdleAfter(FrameVisual before) {
    bool same(double a, double b) => (a - b).abs() < 0.001;
    return people.length == before.people.length &&
        people.every((p) => p.presence < 0.005) &&
        same(ready, before.ready) &&
        same(fade, before.fade) &&
        same(warn, before.warn);
  }

  static PersonVisual _person(
    PersonVisual before,
    Target target,
    TargetFit? fit,
    double Function(double, double, double) toward,
    double dt,
  ) {
    final live = fit?.live;
    final goal = live == null
        ? null
        : Rect.lerp(live.box, target.box, snapOf(fit!.score));
    return PersonVisual(
      box: goal == null
          ? before.box
          : before.box == null || before.presence < 0.05
          ? goal
          : Rect.lerp(before.box, goal, 1 - math.exp(-dt / 0.07)),
      presence: toward(before.presence, live == null ? 0 : 1, 0.12),
      parts: {
        for (final p in GuidePart.values)
          p: toward(
            before.part(p),
            fit?.hits.contains(p) ?? false ? 1 : 0,
            0.07,
          ),
      },
    );
  }
}

class _DynamicFramePainter extends CustomPainter {
  _DynamicFramePainter({
    required this.visual,
    required this.targets,
    required this.action,
    required this.template,
    required this.opacity,
  }) : super(repaint: visual);

  final ValueNotifier<FrameVisual> visual;
  final List<Target> targets;
  final CoachAction action;
  final CompositionTemplate? template;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final v = visual.value;
    final template = this.template;
    if (template != null) {
      final base = Color.lerp(
        Color.lerp(AppTheme.white, AppTheme.amber, v.warn),
        AppTheme.mint,
        v.ready,
      )!;
      final gaze = v.people.isEmpty ? 0.0 : v.people.first.part(GuidePart.gaze);
      CompositionPainter.elements(
        canvas,
        size,
        template,
        color: _tint(base, 0.8 * opacity * v.fade),
        gazeColor: _tint(
          Color.lerp(AppTheme.amber, AppTheme.mint, math.max(gaze, v.ready))!,
          v.fade,
        ),
      );
    }
    for (final (i, target) in targets.indexed) {
      final p = i < v.people.length ? v.people[i] : const PersonVisual();
      switch (target) {
        case FaceTarget():
          _paintFaceTarget(canvas, target, p, v);
        case BodyTarget():
          _paintBodyTarget(canvas, size, target, p, v);
      }
      _paintPerson(canvas, target, p, v);
    }
    if (v.ready > 0.02) _paintReady(canvas, size, v.ready);
  }

  static Color _tint(Color c, double alpha) =>
      c.withValues(alpha: c.a * alpha.clamp(0.0, 1.0));

  static Color _hitColor(double hit, FrameVisual v, double alpha) => _tint(
    Color.lerp(AppTheme.white, AppTheme.mint, math.max(hit, v.ready))!,
    alpha * v.fade,
  );

  /// 얼굴 자리: 허용 반경 원 + 가운데 점 + 크기 모서리
  void _paintFaceTarget(
    Canvas canvas,
    FaceTarget t,
    PersonVisual p,
    FrameVisual v,
  ) {
    final hit = p.part(GuidePart.position);
    // 맞는 순간 '탁' 커졌다 돌아온다
    final pulse = 1 + 0.18 * math.sin(hit * math.pi);
    final color = _hitColor(hit, v, 0.95);
    GuideStroke.draw(
      canvas,
      Path()
        ..addOval(Rect.fromCircle(center: t.center, radius: t.radius * pulse)),
      color: color,
      width: 1.6 + 1.6 * hit,
      dashed: hit < 0.5,
    );
    canvas.drawCircle(
      t.center,
      4.5 * pulse,
      Paint()..color = _tint(AppTheme.ink, 0.7 * v.fade),
    );
    canvas.drawCircle(t.center, 3.2 * pulse, Paint()..color = color);
    GuideStroke.draw(
      canvas,
      _corners(t.box, 8),
      color: _hitColor(p.part(GuidePart.size), v, 0.45),
      width: 1.4,
    );
    if (t.label case final label?) {
      CompositionPainter.text(
        canvas,
        label,
        Offset(t.center.dx, t.box.bottom + 6),
        color,
      );
    }
  }

  /// 전신 자리: 모서리 + 머리선·발끝선
  void _paintBodyTarget(
    Canvas canvas,
    Size size,
    BodyTarget t,
    PersonVisual p,
    FrameVisual v,
  ) {
    final box = t.box;
    GuideStroke.draw(
      canvas,
      _corners(box, 14),
      color: _tint(
        Color.lerp(AppTheme.white, AppTheme.mint, v.ready)!,
        0.65 * v.fade,
      ),
      width: 1.6,
    );
    _anchorLine(
      canvas,
      box.topCenter,
      box.width * 0.5,
      p.part(GuidePart.head),
      v,
      idle: '머리',
      done: '머리 OK',
      above: true,
    );
    final (idle, done) = switch (t.span) {
      BodyAnchor.feet => ('발끝', '발끝 완벽!'),
      BodyAnchor.hips => ('앉은 자리', '자리 OK'),
      _ => ('어깨', '어깨 OK'),
    };
    _anchorLine(
      canvas,
      box.bottomCenter,
      box.width * 0.5,
      p.part(GuidePart.bottom),
      v,
      idle: idle,
      done: done,
      above: false,
    );
  }

  void _anchorLine(
    Canvas canvas,
    Offset center,
    double half,
    double hit,
    FrameVisual v, {
    required String idle,
    required String done,
    required bool above,
  }) {
    final color = _hitColor(hit, v, 0.6 + 0.4 * hit);
    final w = half * (1 + 0.1 * math.sin(hit * math.pi));
    GuideStroke.draw(
      canvas,
      Path()
        ..moveTo(center.dx - w, center.dy)
        ..lineTo(center.dx + w, center.dy),
      color: color,
      width: 1.6 + 2.4 * hit,
    );
    CompositionPainter.text(
      canvas,
      hit > 0.5 ? done : idle,
      center + Offset(0, above ? -19 : 5),
      color,
    );
  }

  /// 사람 프레임 + 거리 화살표
  void _paintPerson(
    Canvas canvas,
    Target target,
    PersonVisual p,
    FrameVisual v,
  ) {
    final box = p.box?.inflate(4);
    if (box == null || p.presence < 0.02 || v.fade < 0.02) return;
    final matched = switch (target) {
      FaceTarget() => math.min(
        p.part(GuidePart.position),
        p.part(GuidePart.size),
      ),
      BodyTarget() => math.min(
        p.part(GuidePart.head),
        p.part(GuidePart.bottom),
      ),
    };
    final color = _tint(
      Color.lerp(AppTheme.amber, AppTheme.mint, math.max(matched, v.ready))!,
      p.presence * v.fade,
    );
    GuideStroke.draw(canvas, _corners(box, 22), color: color, width: 3);
    final outward = switch (action) {
      CoachAction.stepBack || CoachAction.showFeet => true,
      CoachAction.stepCloser => false,
      _ => null,
    };
    if (outward != null) {
      _distanceArrows(canvas, box, v.phase, color, outward);
    }
  }

  /// 크면 바깥으로, 작으면 안으로 움직이는 화살표 (좌우·위아래)
  void _distanceArrows(
    Canvas canvas,
    Rect box,
    double phase,
    Color color,
    bool outward,
  ) {
    for (final delay in const [0.0, 0.5]) {
      final t = (phase + delay) % 1;
      final travel = 8 + 26 * (outward ? t : 1 - t);
      final alpha = math.sin(t * math.pi);
      for (final (dx, dy) in const [(-1, 0), (1, 0), (0, -1), (0, 1)]) {
        final edge =
            box.center + Offset(dx * box.width / 2, dy * box.height / 2);
        final tip = edge + Offset(dx * travel, dy * travel);
        final dir = outward ? 1 : -1;
        final back = Offset(dx * -7.0 * dir, dy * -7.0 * dir);
        final side = Offset(dy * 7.0, dx * 7.0);
        GuideStroke.draw(
          canvas,
          Path()
            ..addPolygon([tip + back + side, tip, tip + back - side], false),
          color: _tint(color, alpha),
          width: 3,
        );
      }
    }
  }

  /// 완성: 뷰파인더 테두리만 얇게 빛남
  void _paintReady(Canvas canvas, Size size, double t) {
    final shape = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(3),
      const Radius.circular(10),
    );
    canvas
      ..drawRRect(
        shape,
        Paint()
          ..color = _tint(AppTheme.mint, 0.5 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      )
      ..drawRRect(
        shape,
        Paint()
          ..color = _tint(AppTheme.mint, t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  static Path _corners(Rect r, double length) {
    final l = math.min(length, math.min(r.width, r.height) / 3);
    final path = Path();
    for (final (p, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      path
        ..moveTo(p.dx + l * dx, p.dy)
        ..lineTo(p.dx, p.dy)
        ..lineTo(p.dx, p.dy + l * dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(_DynamicFramePainter old) =>
      old.targets != targets ||
      old.action != action ||
      old.template != template ||
      old.opacity != opacity ||
      old.visual != visual;
}
