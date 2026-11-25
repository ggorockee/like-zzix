import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/coach.dart';

/// 폰을 어떻게 움직이는지 보여 주는 그림.
///
/// 점선은 지금 자리, 채운 폰은 움직인 뒤, 화살표는 방향이다.
/// - 앞뒤 기울임: 옆에서 본 폰. 왼쪽의 사람이 "나"
/// - 좌우 기울임·옮기기: 앞에서 본 폰
class PhoneMotionIcon extends StatelessWidget {
  const PhoneMotionIcon({
    super.key,
    required this.motion,
    required this.color,
    this.height = 30,
  });

  final PhoneMotion motion;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(height * 1.2, height),
    painter: _PhoneMotionPainter(motion, color),
  );
}

class _PhoneMotionPainter extends CustomPainter {
  const _PhoneMotionPainter(this.motion, this.color);

  final PhoneMotion motion;
  final Color color;

  /// 36×30 기준으로 그린다.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 30);
    switch (motion) {
      case PhoneMotion.topToMe:
        _tilt(canvas, -1);
      case PhoneMotion.topAway:
        _tilt(canvas, 1);
      case PhoneMotion.topLeft:
        _lean(canvas, -1);
      case PhoneMotion.topRight:
        _lean(canvas, 1);
      case PhoneMotion.up:
        _slide(canvas, const Offset(0, -1));
      case PhoneMotion.down:
        _slide(canvas, const Offset(0, 1));
      case PhoneMotion.left:
        _slide(canvas, const Offset(-1, 0));
      case PhoneMotion.right:
        _slide(canvas, const Offset(1, 0));
    }
  }

  Paint get _line => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _fill => Paint()..color = color;

  /// 옆에서 본 폰이 아래 끝을 축으로 기운다 ([dir] −1: 내 쪽(왼쪽), 1: 내 반대쪽(오른쪽)).
  void _tilt(Canvas canvas, double dir) {
    canvas
      ..drawCircle(const Offset(5, 9), 3.6, _fill)
      ..drawPath(
        Path()
          ..moveTo(0, 25)
          ..quadraticBezierTo(0, 15, 5, 15)
          ..quadraticBezierTo(10, 15, 10, 25)
          ..close(),
        _fill,
      );
    const pivot = Offset(23, 27);
    _dashed(canvas, pivot, const Offset(23, 6));
    const angle = 26 * math.pi / 180;
    final top = pivot + Offset(dir * math.sin(angle), -math.cos(angle)) * 20;
    canvas.drawLine(pivot, top, _line..strokeWidth = 4.5);
    _arc(canvas, pivot, 24, dir * 4 * math.pi / 180, dir * angle * 1.05);
  }

  /// 앞에서 본 폰이 좌우로 기운다.
  void _lean(Canvas canvas, double dir) {
    const pivot = Offset(18, 27);
    const angle = 22 * math.pi / 180;
    canvas
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(dir * angle);
    _phone(canvas, const Rect.fromLTWH(-5.5, -19, 11, 19));
    canvas.restore();
    _dashed(canvas, pivot, const Offset(18, 5));
    _arc(canvas, pivot, 24, dir * 2 * math.pi / 180, dir * angle * 1.5);
  }

  /// 세운 폰을 그대로 옮긴다.
  void _slide(Canvas canvas, Offset dir) {
    final vertical = dir.dx == 0;
    final phone = vertical
        ? const Rect.fromLTWH(6, 5, 12, 20)
        : Rect.fromLTWH(dir.dx < 0 ? 22 : 2, 5, 12, 20);
    _phone(canvas, phone);
    final center = vertical
        ? const Offset(26, 15)
        : Offset(dir.dx < 0 ? 11 : 25, 15);
    final reach = dir * (vertical ? 10 : 7.5);
    _arrow(canvas, center - reach, center + reach);
  }

  void _phone(Canvas canvas, Rect r) {
    canvas
      ..drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2.6)), _line)
      ..drawLine(
        Offset(r.center.dx - 1.5, r.bottom - 3.2),
        Offset(r.center.dx + 1.5, r.bottom - 3.2),
        _line..strokeWidth = 1.4,
      );
  }

  void _dashed(Canvas canvas, Offset a, Offset b) {
    final length = (b - a).distance;
    final step = (b - a) / length;
    for (var d = 0.0; d < length; d += 5) {
      canvas.drawLine(
        a + step * d,
        a + step * math.min(d + 2.2, length),
        _line..strokeWidth = 1.4,
      );
    }
  }

  /// [from]→[to] (위쪽 0, 오른쪽 +)로 도는 화살표
  void _arc(Canvas canvas, Offset pivot, double r, double from, double to) {
    Offset at(double a) => pivot + Offset(math.sin(a), -math.cos(a)) * r;
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: r),
      from - math.pi / 2,
      to - from,
      false,
      _line,
    );
    final heading =
        Offset(math.cos(to), math.sin(to)) * (to > from ? 1.0 : -1.0);
    _head(canvas, at(to), heading);
  }

  void _arrow(Canvas canvas, Offset a, Offset b) {
    canvas.drawLine(a, b, _line..strokeWidth = 2.6);
    _head(canvas, b, (b - a) / (b - a).distance);
  }

  void _head(Canvas canvas, Offset tip, Offset dir) {
    final side = Offset(-dir.dy, dir.dx);
    canvas.drawPath(
      Path()..addPolygon([
        tip - dir * 4.2 + side * 3.6,
        tip + dir * 0.8,
        tip - dir * 4.2 - side * 3.6,
      ], false),
      _line..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(_PhoneMotionPainter old) =>
      old.motion != motion || old.color != color;
}
