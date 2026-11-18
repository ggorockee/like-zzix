import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/pose_match.dart';
import 'package:likezzix/models/preset.dart';

/// 서 있는 사람 (프레임 정규화 좌표, 13개 비교 관절 모두 보임)
List<PoseLandmark> standing({
  double dx = 0,
  double dy = 0,
  double scale = 1,
  double visible = 0.95,
  Set<int> hidden = const {},
}) {
  const base = {
    0: (0.50, 0.15),
    11: (0.58, 0.26),
    12: (0.42, 0.26),
    13: (0.61, 0.38),
    14: (0.39, 0.38),
    15: (0.62, 0.49),
    16: (0.38, 0.49),
    23: (0.55, 0.50),
    24: (0.45, 0.50),
    25: (0.56, 0.68),
    26: (0.44, 0.68),
    27: (0.57, 0.86),
    28: (0.43, 0.86),
  };
  return [
    for (var i = 0; i < PoseIndex.count; i++)
      if (base[i] case (final x, final y))
        PoseLandmark(
          0.5 + (x - 0.5) * scale + dx,
          0.5 + (y - 0.5) * scale + dy,
          hidden.contains(i) ? 0.1 : visible,
        )
      else
        const PoseLandmark(0, 0, 0),
  ];
}

void main() {
  final reference = standing();

  PoseMatchResult eval(List<PoseLandmark>? live, [PoseMatcher? m]) =>
      (m ?? PoseMatcher()).evaluate(reference, live, aspectRatio: 1);

  test('같은 자세·위치면 오차 0, 일치', () {
    final r = eval(standing());
    expect(r.error, closeTo(0, 1e-9));
    expect(r.matched, isTrue);
    expect(r.hint, PoseHint.matched);
    expect(r.score, 100);
    expect(r.jointOk.values, everyElement(isTrue));
  });

  test('사람이 없으면 noPerson', () {
    expect(eval(null).hint, PoseHint.noPerson);
  });

  test('관절이 많이 가려지면 몸이 더 보이게 안내', () {
    final r = eval(standing(hidden: {23, 24, 25, 26, 27, 28}));
    expect(r.hint, PoseHint.showMoreBody);
    expect(r.matched, isFalse);
  });

  test('작게 보이면 다가가기, 크게 보이면 물러나기', () {
    expect(eval(standing(scale: 0.7)).hint, PoseHint.stepCloser);
    expect(eval(standing(scale: 1.35)).hint, PoseHint.stepBack);
  });

  test('오른쪽으로 치우치면 카메라를 오른쪽으로', () {
    expect(eval(standing(dx: 0.12)).hint, PoseHint.panRight);
    expect(eval(standing(dx: -0.12)).hint, PoseHint.panLeft);
  });

  test('아래로 치우치면 폰 높이를 낮추기', () {
    expect(eval(standing(dy: 0.12)).hint, PoseHint.lowerPhone);
    expect(eval(standing(dy: -0.12)).hint, PoseHint.raisePhone);
  });

  test('히스테리시스: 진입 10% 미만, 해제 13% 초과', () {
    final m = PoseMatcher();
    // 기준 길이 = 몸통(0.24) → 오차율 = dx / 0.24
    expect(eval(standing(dx: 0.026), m).matched, isFalse); // 10.8%: 진입 못 함
    expect(eval(standing(dx: 0.02), m).matched, isTrue); // 8.3%
    expect(eval(standing(dx: 0.029), m).matched, isTrue); // 12.1% 유지
    expect(eval(standing(dx: 0.033), m).matched, isFalse); // 13.8% 해제
    expect(eval(standing(dx: 0.029), m).matched, isFalse); // 재진입은 10% 기준
  });

  test('레퍼런스에서 안 보이는 관절은 비교하지 않음 (상반신 프리셋)', () {
    final upper = standing(hidden: {23, 24, 25, 26, 27, 28});
    final r = PoseMatcher().evaluate(
      upper,
      standing(visible: 0.95),
      aspectRatio: 1,
    );
    expect(r.matched, isTrue);
    expect(r.jointOk.keys, isNot(contains(25)));
  });
}
