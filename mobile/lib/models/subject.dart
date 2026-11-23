import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'preset.dart';

/// 인물의 기준점.
enum BodyAnchor { head, shoulders, hips, feet }

/// 포즈에서 뽑은 인물 기준점 (좌표는 뷰파인더 px). 보이지 않는 기준점은 빠진다.
@immutable
class BodyPoints {
  const BodyPoints(this.points, {required this.halfWidth});

  /// 포즈 관절(뷰파인더 0~1)에서 기준점을 뽑는다. 머리나 어깨가 안 보이면 null.
  static BodyPoints? fromLandmarks(List<PoseLandmark>? landmarks, Size finder) {
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
    return BodyPoints(
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

  BodyPoints lerpTo(BodyPoints other, double t) => BodyPoints({
    for (final e in other.points.entries)
      e.key: points[e.key] == null
          ? e.value
          : Offset.lerp(points[e.key], e.value, t)!,
  }, halfWidth: halfWidth + (other.halfWidth - halfWidth) * t);
}

/// 화면에서 찾은 인물 하나 (좌표는 뷰파인더 px).
@immutable
class LivePerson {
  const LivePerson({required this.box, this.yawDeg, this.body});

  factory LivePerson.face(Rect box, {double? yawDeg}) =>
      LivePerson(box: box, yawDeg: yawDeg);

  factory LivePerson.body(BodyPoints body, BodyAnchor span) {
    final head = body[BodyAnchor.head]!;
    final bottom = body[span];
    final cx = bottom == null ? head.dx : (head.dx + bottom.dx) / 2;
    return LivePerson(
      box: Rect.fromLTRB(
        cx - body.halfWidth,
        head.dy,
        cx + body.halfWidth,
        bottom?.dy ?? head.dy + body.halfWidth * 4,
      ),
      body: body,
    );
  }

  /// 얼굴 상자 또는 머리~[BodyAnchor] 상자
  final Rect box;

  /// 얼굴 좌우 회전. 화면 오른쪽을 보면 +.
  final double? yawDeg;

  /// 포즈로 찾은 경우의 기준점
  final BodyPoints? body;

  LivePerson lerpTo(LivePerson other, double t) => LivePerson(
    box: Rect.lerp(box, other.box, t)!,
    yawDeg: yawDeg == null || other.yawDeg == null
        ? other.yawDeg
        : yawDeg! + (other.yawDeg! - yawDeg!) * t,
    body: body == null || other.body == null
        ? other.body
        : body!.lerpTo(other.body!, t),
  );
}
