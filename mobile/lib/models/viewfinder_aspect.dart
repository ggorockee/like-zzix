import 'dart:math' as math;
import 'dart:ui';

/// 화면 비율 (세로로 들었을 때 가로/세로). 저장 사진도 이 비율로 잘린다.
enum ViewfinderAspect {
  r4x3('4:3', 3 / 4),
  r16x9('16:9', 9 / 16),
  r1x1('1:1', 1);

  const ViewfinderAspect(this.label, this.ratio);

  final String label;
  final double ratio;

  ViewfinderAspect get next => values[(index + 1) % values.length];

  /// 화면에서 뷰파인더가 놓일 자리. 위([top])·아래([bottom]) 컨트롤 사이에 맞으면 그 가운데,
  /// 넘치면 위쪽 안전 영역([safeTop])부터 채운다.
  Rect layout(
    Size screen, {
    required double safeTop,
    required double top,
    required double bottom,
  }) {
    var width = screen.width;
    var height = width / ratio;
    final maxHeight = screen.height - safeTop;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * ratio;
    }
    final free = screen.height - top - bottom - height;
    final y = free >= 0
        ? top + free / 2
        : math.max(safeTop, math.min(top, screen.height - bottom - height));
    return Rect.fromLTWH((screen.width - width) / 2, y, width, height);
  }
}
