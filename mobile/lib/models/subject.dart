import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'preset.dart';

/// 인물의 기준점.
enum BodyAnchor { head, shoulders, hips, feet }

/// 화면 속 인물 하나 (좌표는 뷰파인더 px). 보이지 않는 기준점은 빠진다.
@immutable
class Subject {
  const Subject(this.points, {required this.halfWidth});

  /// 포즈 관절(뷰파인더 0~1)에서 기준점을 뽑는다. 머리나 어깨가 안 보이면 null.
  static Subject? fromLandmarks(List<PoseLandmark>? landmarks, Size finder) {
    if (landmarks == null || landmarks.length < PoseIndex.count) return null;
    Offset? at(int i) {
      final l = landmarks[i];
      return l.isVisible
          ? Offset(l.x * finder.width, l.y * finder.height)
          : null;
    }

    Offset? mid(int a, int b) {
      final p = at(a), q = at(b);
      return p == null || q == null ? p ?? q : Offset.lerp(p, q, 0.5);
    }

    final nose = at(PoseIndex.nose);
    final shoulders = mid(PoseIndex.leftShoulder, PoseIndex.rightShoulder);
    if (nose == null || shoulders == null) return null;
    // 정수리는 관절이 없으므로 코~어깨 거리로 추정 (성인 인체 비율)
    final head = Offset(
      nose.dx,
      nose.dy - (shoulders.dy - nose.dy).abs() * 0.6,
    );

    Offset? feet;
    for (final i in const [27, 28, 29, 30, 31, 32]) {
      final p = at(i);
      if (p != null && (feet == null || p.dy > feet.dy)) feet = p;
    }
    final ankles = mid(PoseIndex.leftAnkle, PoseIndex.rightAnkle);
    if (feet != null && ankles != null) feet = Offset(ankles.dx, feet.dy);
    // 화면 아래로 나간 발은 추정값이므로 보이지 않는 것으로 본다
    if (feet != null && feet.dy > finder.height * 1.005) feet = null;

    final left = at(PoseIndex.leftShoulder);
    final right = at(PoseIndex.rightShoulder);
    final shoulderWidth = left != null && right != null
        ? (left - right).distance
        : 0.0;
    final hips = mid(PoseIndex.leftHip, PoseIndex.rightHip);
    return Subject(
      {
        BodyAnchor.head: head,
        BodyAnchor.shoulders: shoulders,
        BodyAnchor.hips: ?hips,
        BodyAnchor.feet: ?feet,
      },
      halfWidth: math.max(
        shoulderWidth * 0.9,
        (shoulders.dy - head.dy).abs() * 0.75,
      ),
    );
  }

  final Map<BodyAnchor, Offset> points;

  /// 프레임을 그릴 때 쓰는 몸 반폭
  final double halfWidth;

  Offset? operator [](BodyAnchor a) => points[a];

  Subject lerpTo(Subject other, double t) => Subject({
    for (final e in other.points.entries)
      e.key: points[e.key] == null
          ? e.value
          : Offset.lerp(points[e.key], e.value, t)!,
  }, halfWidth: halfWidth + (other.halfWidth - halfWidth) * t);
}

/// 목표 구도: 인물이 있어야 할 자리와 크기 (좌표는 뷰파인더 px).
@immutable
class SubjectTarget {
  const SubjectTarget(this.subject, {required this.span, required this.finder});

  /// 프리셋과 뷰파인더 크기로 목표를 만든다. 비교할 기준점이 없으면 null.
  static SubjectTarget? of(Preset preset, Size finder) {
    if (finder.isEmpty) return null;
    final template = preset.template;
    if (template != null) {
      final layout = template.layout(finder);
      return SubjectTarget(
        Subject({
          for (final e in template.joints.entries)
            e.key: layout.figure(e.value),
        }, halfWidth: template.halfWidth * layout.scale),
        span: template.span,
        finder: finder,
      );
    }
    // 사진 프리셋: 사진 속 인물의 관절에서 자리·크기만 뽑는다
    final frame = fitFrame(finder, preset.aspectRatio);
    final subject = Subject.fromLandmarks([
      for (final l in preset.landmarks)
        PoseLandmark(
          (frame.left + l.x * frame.width) / finder.width,
          (frame.top + l.y * frame.height) / finder.height,
          // 사진 밖으로 나간 관절은 기준으로 쓰지 않는다
          l.y > 1 || l.x < 0 || l.x > 1 ? 0 : l.likelihood,
        ),
    ], finder);
    if (subject == null) return null;
    return SubjectTarget(
      subject,
      span: subject[BodyAnchor.feet] != null
          ? BodyAnchor.feet
          : subject[BodyAnchor.hips] != null
          ? BodyAnchor.hips
          : BodyAnchor.shoulders,
      finder: finder,
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

  final Subject subject;

  /// 머리끝과 함께 인물 크기를 재는 기준점
  final BodyAnchor span;
  final Size finder;

  double get spanPx => spanOf(subject)!;

  double? spanOf(Subject s) {
    final a = s[BodyAnchor.head], b = s[span];
    return a == null || b == null ? null : math.max(1, b.dy - a.dy);
  }

  /// 실제 몸 길이(m, 성인 평균): 거리 안내에만 쓰는 근삿값
  double get spanMeters => switch (span) {
    BodyAnchor.feet => 1.65,
    BodyAnchor.hips => 0.85,
    BodyAnchor.shoulders || BodyAnchor.head => 0.31,
  };
}

/// 지금 할 행동.
enum CoachAction {
  findPerson,
  showHead,
  showFeet,
  stepBack,
  stepCloser,
  panLeft,
  panRight,
  raisePhone,
  lowerPhone,
  hold,
}

/// 목표 대비 현재 인물.
@immutable
class SubjectFit {
  const SubjectFit({
    required this.action,
    required this.score,
    this.scale = 1,
    this.steps = 0,
    this.hits = const {},
  });

  static const none = SubjectFit(action: CoachAction.findPerson, score: 0);

  final CoachAction action;

  /// 0~100. 크기·좌우·머리·발끝 오차 중 가장 큰 것 기준이며, 모두 허용 오차 안이면 90 이상.
  final double score;

  /// 현재 크기 ÷ 목표 크기
  final double scale;

  /// 앞뒤로 움직일 걸음 수 (0이면 "조금만")
  final int steps;

  /// 목표 자리에 들어온 기준점
  final Set<BodyAnchor> hits;

  static const enterScore = 90.0;
  static const exitScore = 86.0;

  static const _scaleTolerance = 0.10;
  static const _strideMeters = 0.65;

  /// [focal]은 화면 단위 초점거리(줌 포함). 걸음 수 추정에만 쓴다.
  static SubjectFit evaluate(
    Subject? live,
    SubjectTarget target, {
    required double focal,
    Set<BodyAnchor> previousHits = const {},
  }) {
    if (live == null) return none;
    final goal = target.subject;
    final span = target.spanPx;
    final tolY = span * 0.06;
    final tolX = math.max(target.finder.width * 0.04, span * 0.05);

    // 기준점별 일치 (이미 맞은 점은 1.5배까지 유지)
    final hits = <BodyAnchor>{
      for (final e in goal.points.entries)
        if (live[e.key] case final p?)
          if ((p.dy - e.value.dy).abs() <=
              tolY * (previousHits.contains(e.key) ? 1.5 : 1))
            e.key,
    };

    final head = live[BodyAnchor.head]!;
    if (head.dy < -target.finder.height * 0.01) {
      return SubjectFit(action: CoachAction.showHead, score: 0, hits: hits);
    }
    final liveSpan = target.spanOf(live);
    if (liveSpan == null) {
      return SubjectFit(
        action: target.span == BodyAnchor.feet
            ? CoachAction.showFeet
            : CoachAction.stepBack,
        score: 0,
        hits: hits,
      );
    }

    final scale = liveSpan / span;
    final bottom = live[target.span]!;
    final dx =
        (head.dx + bottom.dx) / 2 -
        (goal[BodyAnchor.head]!.dx + goal[target.span]!.dx) / 2;
    final headDy = head.dy - goal[BodyAnchor.head]!.dy;
    final bottomDy = bottom.dy - goal[target.span]!.dy;
    final worst = [
      (scale - 1).abs() / _scaleTolerance,
      dx.abs() / tolX,
      headDy.abs() / tolY,
      bottomDy.abs() / tolY,
    ].reduce(math.max);
    final score = (100 - worst * 10).clamp(0.0, 100.0);

    final dy = (headDy + bottomDy) / 2;
    final CoachAction action;
    if (scale > 1 + _scaleTolerance) {
      action = CoachAction.stepBack;
    } else if (scale < 1 - _scaleTolerance) {
      action = CoachAction.stepCloser;
    } else if (dx.abs() / tolX > 1 && dx.abs() / tolX >= dy.abs() / tolY) {
      // 사람이 목표보다 오른쪽이면 폰을 오른쪽으로 돌려야 왼쪽으로 온다
      action = dx > 0 ? CoachAction.panRight : CoachAction.panLeft;
    } else if (dy.abs() > tolY * 0.8) {
      action = dy > 0 ? CoachAction.lowerPhone : CoachAction.raisePhone;
    } else if (score < enterScore) {
      action = scale > 1 ? CoachAction.stepBack : CoachAction.stepCloser;
    } else {
      action = CoachAction.hold;
    }

    // 목표 거리와 현재 거리의 차이 → 걸음 수
    final distance = target.spanMeters * focal / span;
    final move = (distance / scale - distance).abs();
    return SubjectFit(
      action: action,
      score: score,
      scale: scale,
      steps: (move / _strideMeters).round().clamp(0, 5),
      hits: hits,
    );
  }
}
