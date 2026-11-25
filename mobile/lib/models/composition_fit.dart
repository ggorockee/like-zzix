import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'composition.dart';
import 'preset.dart';
import 'subject.dart';

/// 화면에서 초록으로 반응하는 부분.
enum GuidePart { position, size, gaze, head, bottom }

/// 지금 할 행동.
enum CoachAction {
  findPerson,
  findSecond,
  showHead,
  showFeet,
  stepBack,
  stepCloser,
  moveLeft,
  moveRight,
  raisePhone,
  lowerPhone,
  lookLeft,
  lookRight,

  /// 여러 명일 때 한 사람만 옮기기
  personLeft,
  personRight,
  personUp,
  personDown,
  personCloser,
  personBack,
  hold,
}

/// 뷰파인더 크기에 맞춘 인물 자리 (px).
@immutable
sealed class Target {
  const Target({this.label});

  static List<Target> of(Preset preset, Size finder) {
    if (finder.isEmpty) return const [];
    final template = preset.template;
    if (template != null) {
      return [
        for (final s in template.subjects)
          switch (s) {
            FaceSpec() => FaceTarget.of(s, finder),
            BodySpec() => BodyTarget.of(s, finder),
          },
      ];
    }
    final photo = BodyTarget.ofPhoto(preset, finder);
    return photo == null ? const [] : [photo];
  }

  final String? label;

  /// 인물을 자리에 배정할 때 쓰는 중심
  Offset get center;

  /// 크기를 비교하는 목표 높이
  double get size;

  /// 자석이 붙었을 때의 프레임
  Rect get box;

  /// 실제 길이(m, 성인 평균): 걸음 수 안내에만 쓰는 근삿값
  double get meters;

  TargetFit evaluate(LivePerson? live, Set<GuidePart> previous);
}

/// 인물 한 명의 판정 결과.
@immutable
class TargetFit {
  const TargetFit({
    required this.live,
    this.positionTerm = double.infinity,
    this.sizeTerm = double.infinity,
    this.gazeTerm = 0,
    this.scale = 1,
    this.delta = Offset.zero,
    this.tolerance = 1,
    this.hits = const {},
    this.cut,
  });

  final LivePerson? live;

  /// 오차 ÷ 허용 오차 (1 이하면 통과)
  final double positionTerm;
  final double sizeTerm;
  final double gazeTerm;

  /// 현재 크기 ÷ 목표 크기
  final double scale;

  /// 목표에서 벗어난 거리 (px)
  final Offset delta;

  /// 위치 허용 오차 (px)
  final double tolerance;
  final Set<GuidePart> hits;

  /// 화면 밖으로 잘린 부분
  final CoachAction? cut;

  /// 0~100. 모든 조건이 허용 오차 안이면 90 이상.
  double get score => live == null || cut != null
      ? 0
      : (100 - 10 * [positionTerm, sizeTerm, gazeTerm].reduce(math.max)).clamp(
          0,
          100,
        );
}

@immutable
class FaceTarget extends Target {
  const FaceTarget({
    required this.center,
    required this.radius,
    required this.sizeMin,
    required this.sizeMax,
    required this.gaze,
    super.label,
  });

  factory FaceTarget.of(FaceSpec s, Size finder) => FaceTarget(
    center: Offset(s.anchor.dx * finder.width, s.anchor.dy * finder.height),
    radius: s.radius * finder.height,
    sizeMin: s.sizeMin * finder.height,
    sizeMax: s.sizeMax * finder.height,
    gaze: s.gaze,
    label: s.label,
  );

  /// 이 각도 이상 돌려야 그쪽을 보는 것으로 인정
  static const gazeDeg = 12.0;

  @override
  final Offset center;
  final double radius;
  final double sizeMin;
  final double sizeMax;
  final Gaze? gaze;

  /// 범위의 기하 중앙
  @override
  double get size => math.sqrt(sizeMin * sizeMax);

  @override
  Rect get box =>
      Rect.fromCenter(center: center, width: size * 0.8, height: size);

  @override
  double get meters => 0.19;

  @override
  TargetFit evaluate(LivePerson? live, Set<GuidePart> previous) {
    if (live == null) return const TargetFit(live: null);
    final delta = live.box.center - center;
    final position = delta.distance / radius;
    final scale = live.box.height / size;
    final sizeTerm = math.log(scale).abs() / math.log(sizeMax / size);
    final yaw = live.yawDeg;
    final gazeTerm = gaze == null
        ? 0.0
        : yaw == null
        ? 2.0
        // 기준 각도에서 1, 정면에서 2
        : math.max(
            0.0,
            1 + (gazeDeg - (gaze == Gaze.left ? -yaw : yaw)) / gazeDeg,
          );
    bool hit(double term, GuidePart part) =>
        term <= (previous.contains(part) ? 1.4 : 1);
    return TargetFit(
      live: live,
      positionTerm: position,
      sizeTerm: sizeTerm,
      gazeTerm: gazeTerm,
      scale: scale,
      delta: delta,
      tolerance: radius,
      hits: {
        if (hit(position, GuidePart.position)) GuidePart.position,
        if (hit(sizeTerm, GuidePart.size)) GuidePart.size,
        if (gaze != null && hit(gazeTerm, GuidePart.gaze)) GuidePart.gaze,
      },
    );
  }
}

@immutable
class BodyTarget extends Target {
  const BodyTarget({
    required this.head,
    required this.bottom,
    required this.span,
    required this.finder,
    required this.halfWidth,
    super.label,
  });

  factory BodyTarget.of(BodySpec s, Size finder) {
    Offset px(Offset p) => Offset(p.dx * finder.width, p.dy * finder.height);
    final head = px(s.head);
    final bottom = px(s.bottom);
    return BodyTarget(
      head: head,
      bottom: bottom,
      span: s.span,
      finder: finder,
      halfWidth:
          (bottom.dy - head.dy) *
          switch (s.span) {
            BodyAnchor.feet => 0.19,
            BodyAnchor.hips => 0.36,
            _ => 0.7,
          },
      label: s.label,
    );
  }

  /// 사진 프리셋: 사진 속 인물의 관절에서 자리·크기만 뽑는다.
  static BodyTarget? ofPhoto(Preset preset, Size finder) {
    final frame = fitFrame(finder, preset.aspectRatio);
    final body = BodyPoints.fromLandmarks([
      for (final l in preset.landmarks)
        PoseLandmark(
          (frame.left + l.x * frame.width) / finder.width,
          (frame.top + l.y * frame.height) / finder.height,
          // 사진 밖으로 나간 관절은 기준으로 쓰지 않는다
          l.y > 1 || l.x < 0 || l.x > 1 ? 0 : l.likelihood,
        ),
    ], finder);
    if (body == null) return null;
    final span = body[BodyAnchor.feet] != null
        ? BodyAnchor.feet
        : body[BodyAnchor.hips] != null
        ? BodyAnchor.hips
        : BodyAnchor.shoulders;
    return BodyTarget(
      head: body[BodyAnchor.head]!,
      bottom: body[span]!,
      span: span,
      finder: finder,
      halfWidth: body.halfWidth,
    );
  }

  /// [size] 안에 [aspectRatio] 사각형을 가운데 맞춤.
  static Rect fitFrame(Size size, double aspectRatio) {
    var width = size.width;
    var height = width / aspectRatio;
    if (height > size.height) {
      height = size.height;
      width = height * aspectRatio;
    }
    return Rect.fromLTWH(
      (size.width - width) / 2,
      (size.height - height) / 2,
      width,
      height,
    );
  }

  final Offset head;
  final Offset bottom;
  final BodyAnchor span;
  final Size finder;
  final double halfWidth;

  static const _scaleTolerance = 0.10;

  @override
  Offset get center => Offset.lerp(head, bottom, 0.5)!;

  @override
  double get size => math.max(1, bottom.dy - head.dy);

  @override
  Rect get box => Rect.fromLTRB(
    center.dx - halfWidth,
    head.dy,
    center.dx + halfWidth,
    bottom.dy,
  );

  @override
  double get meters => switch (span) {
    BodyAnchor.feet => 1.65,
    BodyAnchor.hips => 0.85,
    BodyAnchor.shoulders || BodyAnchor.head => 0.31,
  };

  @override
  TargetFit evaluate(LivePerson? live, Set<GuidePart> previous) {
    final body = live?.body;
    if (body == null) return const TargetFit(live: null);
    final liveHead = body[BodyAnchor.head]!;
    final liveBottom = body[span];
    final tolY = size * 0.06;
    final tolX = math.max(finder.width * 0.04, size * 0.05);
    final headDy = liveHead.dy - head.dy;
    final bottomDy = liveBottom == null ? null : liveBottom.dy - bottom.dy;
    bool hit(double? dy, GuidePart part) =>
        dy != null && dy.abs() <= tolY * (previous.contains(part) ? 1.5 : 1);
    final hits = {
      if (hit(headDy, GuidePart.head)) GuidePart.head,
      if (hit(bottomDy, GuidePart.bottom)) GuidePart.bottom,
    };
    final cut = liveHead.dy < -finder.height * 0.01
        ? CoachAction.showHead
        : liveBottom == null
        ? (span == BodyAnchor.feet
              ? CoachAction.showFeet
              : CoachAction.stepBack)
        : null;
    if (cut != null) return TargetFit(live: live, hits: hits, cut: cut);

    final scale = math.max(1.0, liveBottom!.dy - liveHead.dy) / size;
    final dx = (liveHead.dx + liveBottom.dx) / 2 - center.dx;
    return TargetFit(
      live: live,
      positionTerm: [
        dx.abs() / tolX,
        headDy.abs() / tolY,
        bottomDy!.abs() / tolY,
      ].reduce(math.max),
      sizeTerm: (scale - 1).abs() / _scaleTolerance,
      scale: scale,
      delta: Offset(dx, (headDy + bottomDy) / 2),
      tolerance: tolY,
      hits: hits,
    );
  }
}

/// 구도 전체의 판정 결과.
@immutable
class CompositionFit {
  const CompositionFit({
    required this.targets,
    required this.action,
    this.steps = 0,
    this.who,
  });

  static const none = CompositionFit(
    targets: [],
    action: CoachAction.findPerson,
  );

  final List<TargetFit> targets;
  final CoachAction action;

  /// 앞뒤로 움직일 걸음 수 (0이면 "반 걸음")
  final int steps;

  /// 한 사람만 옮길 때 누구인지 (앞사람·왼쪽 사람 등)
  final String? who;

  static const enterScore = 90.0;
  static const exitScore = 86.0;
  static const _strideMeters = 0.65;

  double get score => targets.isEmpty
      ? 0
      : targets.map((t) => t.score).reduce((a, b) => math.min(a, b));

  bool get hasPerson => targets.any((t) => t.live != null);
  bool get hasEveryone =>
      targets.isNotEmpty && targets.every((t) => t.live != null);

  /// [people]을 자리에 배정해 판정한다. [focal]은 화면 단위 초점거리(줌 포함).
  static CompositionFit evaluate(
    List<Target> targets,
    List<LivePerson> people, {
    required double focal,
    List<Set<GuidePart>> previous = const [],
  }) {
    final assigned = assign(targets, people);
    return evaluateAssigned(
      targets,
      assigned,
      focal: focal,
      previous: previous,
    );
  }

  static CompositionFit evaluateAssigned(
    List<Target> targets,
    List<LivePerson?> assigned, {
    required double focal,
    List<Set<GuidePart>> previous = const [],
  }) {
    final fits = [
      for (final (i, t) in targets.indexed)
        t.evaluate(assigned[i], i < previous.length ? previous[i] : const {}),
    ];
    CompositionFit result(CoachAction a, {int steps = 0, String? who}) =>
        CompositionFit(targets: fits, action: a, steps: steps, who: who);

    if (fits.every((f) => f.live == null)) {
      return result(CoachAction.findPerson);
    }
    if (fits.any((f) => f.live == null)) return result(CoachAction.findSecond);
    for (final f in fits) {
      if (f.cut case final cut?) return result(cut);
    }

    // 1) 거리: 모두 같은 방향으로 크거나 작으면 촬영자가 움직인다
    final sizeOff = [for (final f in fits) f.sizeTerm > 1];
    if (sizeOff.contains(true)) {
      final i = _worst(fits, (f) => f.sizeTerm);
      final big = fits[i].scale > 1;
      final together = fits.every((f) => (f.scale > 1) == big);
      final steps = _steps(targets[i], fits[i].scale, focal);
      if (fits.length == 1 || together) {
        return result(
          big ? CoachAction.stepBack : CoachAction.stepCloser,
          steps: steps,
        );
      }
      return result(
        big ? CoachAction.personBack : CoachAction.personCloser,
        steps: steps,
        who: _name(targets, i),
      );
    }

    // 2) 위치: 평균 어긋남은 폰으로, 나머지는 그 사람이 움직인다
    if (fits.any((f) => f.positionTerm > 1)) {
      final mean =
          fits.map((f) => f.delta).reduce((a, b) => a + b) /
          fits.length.toDouble();
      final tol = fits.map((f) => f.tolerance).reduce(math.min);
      if (fits.length == 1 || mean.distance > tol * 0.6) {
        if (mean.dx.abs() >= mean.dy.abs()) {
          // 사람이 목표보다 오른쪽이면 폰을 오른쪽으로 옮겨야 왼쪽으로 온다
          // (전면 카메라는 화면이 거울처럼 보여 같은 방향)
          return result(
            mean.dx > 0 ? CoachAction.moveRight : CoachAction.moveLeft,
          );
        }
        return result(
          mean.dy > 0 ? CoachAction.lowerPhone : CoachAction.raisePhone,
        );
      }
      final i = _worst(fits, (f) => f.positionTerm);
      final d = fits[i].delta;
      return result(
        d.dx.abs() >= d.dy.abs()
            ? (d.dx > 0 ? CoachAction.personLeft : CoachAction.personRight)
            : (d.dy > 0 ? CoachAction.personUp : CoachAction.personDown),
        who: _name(targets, i),
      );
    }

    // 3) 시선
    for (final (i, f) in fits.indexed) {
      if (f.gazeTerm > 1) {
        return result(
          (targets[i] as FaceTarget).gaze == Gaze.left
              ? CoachAction.lookLeft
              : CoachAction.lookRight,
        );
      }
    }
    return result(CoachAction.hold);
  }

  /// 자리마다 가장 알맞은 사람을 고른다 (거리 + 크기 차이의 합이 최소).
  static List<LivePerson?> assign(
    List<Target> targets,
    List<LivePerson> people,
  ) {
    bool suits(Target t, LivePerson p) => (t is BodyTarget) == (p.body != null);
    double cost(Target t, LivePerson p) =>
        (p.box.center - t.center).distance / 200 +
        math.log(math.max(1, p.box.height) / t.size).abs() * 0.6;

    var best = List<LivePerson?>.filled(targets.length, null);
    var bestCost = double.infinity;
    void search(int i, Set<int> used, List<LivePerson?> chosen, double sum) {
      if (sum >= bestCost) return;
      if (i == targets.length) {
        bestCost = sum;
        best = [...chosen];
        return;
      }
      for (var j = 0; j < people.length; j++) {
        if (used.contains(j) || !suits(targets[i], people[j])) continue;
        search(
          i + 1,
          {...used, j},
          [...chosen, people[j]],
          sum + cost(targets[i], people[j]),
        );
      }
      // 맞는 사람이 모자라면 자리를 비운다 (비용이 커서 마지막 선택)
      search(i + 1, used, [...chosen, null], sum + 100);
    }

    search(0, const {}, const [], 0);
    return best;
  }

  static int _worst(List<TargetFit> fits, double Function(TargetFit) term) {
    var worst = 0;
    for (var i = 1; i < fits.length; i++) {
      if (term(fits[i]) > term(fits[worst])) worst = i;
    }
    return worst;
  }

  static int _steps(Target t, double scale, double focal) {
    final distance = t.meters * focal / t.size;
    final move = (distance / scale - distance).abs();
    return (move / _strideMeters).round().clamp(0, 5);
  }

  static String _name(List<Target> targets, int i) {
    final label = targets[i].label;
    if (label != null) return label;
    final leftmost = targets.every((t) => t.center.dx >= targets[i].center.dx);
    return leftmost ? '왼쪽 사람' : '오른쪽 사람';
  }
}
