import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/app_theme.dart';
import '../models/subject.dart';
import '../providers/subject_providers.dart';
import 'guide_stroke.dart';

/// 살아 있는 가이드: 목표 자리 + 사람을 따라다니는 프레임.
///
/// - 머리선·발끝선은 사람이 들어오면 그 선만 초록으로 '탁' 반응
/// - 사람 프레임은 구도가 가까워질수록 목표에 자석처럼 붙음
/// - 크면 바깥으로, 작으면 안으로 벌어지는 화살표
/// - 촬영 순간([ready])에는 모두 사라지고 얇은 초록 테두리만 남음
class DynamicFrame extends StatefulWidget {
  const DynamicFrame({super.key, required this.state, required this.ready});

  final SubjectState? state;
  final bool ready;

  @override
  State<DynamicFrame> createState() => _DynamicFrameState();
}

class _DynamicFrameState extends State<DynamicFrame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = ValueNotifier(const FrameVisual());
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// 포즈 인식(초당 약 10회)보다 부드럽게, 매 프레임 목표 값으로 다가간다.
  void _onTick(Duration elapsed) {
    final dt = math.min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    _frame.value = _frame.value.step(widget.state, widget.ready, dt);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _DynamicFramePainter(
            visual: _frame,
            target: state?.target,
            action: state?.fit.action ?? CoachAction.findPerson,
          ),
        ),
      ),
    );
  }
}

/// 화면에 그려지는 중간 값.
@immutable
class FrameVisual {
  const FrameVisual({
    this.live,
    this.presence = 0,
    this.ready = 0,
    this.hits = const {},
    this.phase = 0,
  });

  /// 사람 프레임 (자석 효과 적용 전의 부드러운 위치)
  final Subject? live;

  /// 사람 프레임 투명도 0~1
  final double presence;

  /// 완성 상태 전환 0~1
  final double ready;

  /// 기준점별 초록 전환 0~1
  final Map<BodyAnchor, double> hits;

  /// 화살표 애니메이션 위상 0~1
  final double phase;

  /// 구도 오차가 이 점수부터 자석이 붙기 시작해 90점에서 완전히 붙는다
  static const _snapFrom = 55.0;

  static double snapOf(double score) {
    final t = ((score - _snapFrom) / (SubjectFit.enterScore - _snapFrom)).clamp(
      0.0,
      1.0,
    );
    return t * t * (3 - 2 * t);
  }

  FrameVisual step(SubjectState? state, bool isReady, double dt) {
    double toward(double from, double to, double tau) =>
        from + (to - from) * (1 - math.exp(-dt / tau));

    final found = state?.live;
    var goal = found;
    if (found != null) {
      goal = found.lerpTo(state!.target.subject, snapOf(state.fit.score));
    }
    return FrameVisual(
      live: goal == null
          ? live
          : live == null || presence < 0.05
          ? goal
          : live!.lerpTo(goal, 1 - math.exp(-dt / 0.07)),
      presence: toward(presence, found == null ? 0 : 1, 0.12),
      ready: toward(ready, isReady ? 1 : 0, 0.14),
      hits: {
        for (final a in BodyAnchor.values)
          a: toward(
            hits[a] ?? 0,
            state?.fit.hits.contains(a) ?? false ? 1 : 0,
            0.07,
          ),
      },
      phase: (phase + dt / 0.9) % 1,
    );
  }
}

class _DynamicFramePainter extends CustomPainter {
  _DynamicFramePainter({
    required this.visual,
    required this.target,
    required this.action,
  }) : super(repaint: visual);

  final ValueNotifier<FrameVisual> visual;
  final SubjectTarget? target;
  final CoachAction action;

  @override
  void paint(Canvas canvas, Size size) {
    final target = this.target;
    if (target == null) return;
    final v = visual.value;
    final fade = 1 - v.ready;
    if (fade > 0.02) {
      _paintTarget(canvas, size, target, v, fade);
      final live = v.live;
      if (live != null && v.presence > 0.02) {
        _paintLive(canvas, target, live, v, fade * v.presence);
      }
    }
    if (v.ready > 0.02) _paintReady(canvas, size, v.ready);
  }

  static Rect _box(Subject s, BodyAnchor span, Subject fallback) {
    final head = s[BodyAnchor.head] ?? fallback[BodyAnchor.head]!;
    final bottom = s[span];
    final cx = bottom == null ? head.dx : (head.dx + bottom.dx) / 2;
    return Rect.fromLTRB(
      cx - s.halfWidth,
      head.dy,
      cx + s.halfWidth,
      bottom?.dy ?? head.dy + s.halfWidth * 3,
    );
  }

  static Color _tint(Color c, double alpha) =>
      c.withValues(alpha: c.a * alpha.clamp(0, 1));

  /// 목표 자리: 옅은 모서리 + 머리선·발끝선
  void _paintTarget(
    Canvas canvas,
    Size size,
    SubjectTarget target,
    FrameVisual v,
    double fade,
  ) {
    final box = _box(target.subject, target.span, target.subject);
    GuideStroke.draw(
      canvas,
      _corners(box, 14),
      color: _tint(AppTheme.white, 0.65 * fade),
      width: 1.6,
    );
    _anchorLine(
      canvas,
      box.topCenter,
      box.width * 0.5,
      v.hits[BodyAnchor.head] ?? 0,
      fade,
      idle: '머리',
      done: '머리 OK',
      above: true,
    );
    final spanHit = v.hits[target.span] ?? 0;
    final (idle, done) = switch (target.span) {
      BodyAnchor.feet => ('발끝', '발끝 완벽!'),
      BodyAnchor.hips => ('앉은 자리', '자리 OK'),
      _ => ('어깨', '어깨 OK'),
    };
    _anchorLine(
      canvas,
      box.bottomCenter,
      // 발끝선은 화면 폭 가까이 길게: 촬영자가 바닥 기준으로 삼는다
      target.span == BodyAnchor.feet
          ? math.max(box.width, size.width * 0.42)
          : box.width * 0.5,
      spanHit,
      fade,
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
    double fade, {
    required String idle,
    required String done,
    required bool above,
  }) {
    final color = _tint(
      Color.lerp(AppTheme.white, AppTheme.mint, hit)!,
      (0.55 + 0.45 * hit) * fade,
    );
    // 맞는 순간 살짝 길어지고 굵어짐
    final w = half * (1 + 0.1 * math.sin(hit * math.pi));
    GuideStroke.draw(
      canvas,
      Path()
        ..moveTo(center.dx - w, center.dy)
        ..lineTo(center.dx + w, center.dy),
      color: color,
      width: 1.6 + 2.4 * hit,
    );
    _text(
      canvas,
      hit > 0.5 ? done : idle,
      Offset(center.dx, center.dy + (above ? -17 : 5)),
      color,
      bold: hit > 0.5,
    );
  }

  /// 사람 프레임 + 거리 화살표
  void _paintLive(
    Canvas canvas,
    SubjectTarget target,
    Subject live,
    FrameVisual v,
    double alpha,
  ) {
    final box = _box(live, target.span, target.subject).inflate(6);
    final matched = v.hits.entries
        .where((e) => target.subject.points.containsKey(e.key))
        .fold<double>(1, (m, e) => math.min(m, e.value));
    final color = _tint(
      Color.lerp(AppTheme.amber, AppTheme.mint, matched)!,
      alpha,
    );
    GuideStroke.draw(canvas, _corners(box, 22), color: color, width: 3);
    final eye = live[BodyAnchor.shoulders];
    if (eye != null) {
      canvas.drawCircle(eye, 3, Paint()..color = color);
    }

    final out = switch (action) {
      CoachAction.stepBack || CoachAction.showFeet => true,
      CoachAction.stepCloser => false,
      _ => null,
    };
    if (out != null) _distanceArrows(canvas, box, v.phase, color, out);
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
            ..moveTo((tip + back + side).dx, (tip + back + side).dy)
            ..lineTo(tip.dx, tip.dy)
            ..lineTo((tip + back - side).dx, (tip + back - side).dy),
          color: _tint(color, alpha),
          width: 3,
        );
      }
    }
  }

  /// 완성: 뷰파인더 테두리만 얇게 빛남
  void _paintReady(Canvas canvas, Size size, double t) {
    final rect = (Offset.zero & size).deflate(3);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(10));
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

  static void _text(
    Canvas canvas,
    String text,
    Offset topCenter,
    Color color, {
    required bool bold,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          shadows: [Shadow(color: _tint(AppTheme.ink, color.a), blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp
      ..paint(canvas, topCenter - Offset(tp.width / 2, 0))
      ..dispose();
  }

  @override
  bool shouldRepaint(_DynamicFramePainter old) =>
      old.target != target || old.action != action || old.visual != visual;
}
