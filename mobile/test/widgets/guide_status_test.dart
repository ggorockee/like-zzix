import 'package:flutter_test/flutter_test.dart';
import 'package:likezzix/models/attitude.dart';
import 'package:likezzix/models/pose_match.dart';
import 'package:likezzix/providers/pose_providers.dart';
import 'package:likezzix/widgets/guide_status.dart';

AngleGuide angle({
  bool matched = true,
  bool upright = true,
  double delta = 0,
}) => AngleGuide(
  pitchDelta: delta,
  rollDelta: 0,
  matched: matched,
  tilt: matched
      ? TiltHint.none
      : delta > 0
      ? TiltHint.aimUp
      : TiltHint.aimDown,
  level: LevelHint.none,
  upright: upright,
);

PoseMatchState pose(PoseHint hint, {bool perfect = false, double? error}) =>
    PoseMatchState(
      result: PoseMatchResult(
        hint: hint,
        matched: hint == PoseHint.matched,
        error: error,
      ),
      live: null,
      perfect: perfect,
    );

String? text(AngleGuide? a, PoseMatchState? p) =>
    GuideStatus.message(angle: a, pose: p, hasPreset: true)?.$2;

void main() {
  test('Perfect가 최우선', () {
    expect(
      text(angle(matched: false), pose(PoseHint.matched, perfect: true)),
      '지금 찍으세요!',
    );
  });

  test('폰을 눕히면 세우라는 안내가 사람 인식보다 우선', () {
    expect(
      text(angle(matched: false, upright: false), pose(PoseHint.noPerson)),
      '폰을 세워서 들어 주세요',
    );
  });

  test('사람이 없으면 각도보다 먼저 사람 안내', () {
    expect(
      text(angle(matched: false, delta: 10), pose(PoseHint.noPerson)),
      '사람이 화면에 보이게 해 주세요',
    );
  });

  test('각도가 틀리면 위치 안내보다 각도 먼저', () {
    expect(
      text(angle(matched: false, delta: 8), pose(PoseHint.stepCloser)),
      '카메라를 위로 8° 더 향하게',
    );
  });

  test('각도가 맞으면 위치·포즈 안내', () {
    expect(text(angle(), pose(PoseHint.stepCloser)), '다가가거나 줌을 올려요');
    expect(text(angle(), pose(PoseHint.lowerPhone)), '폰 높이를 조금 낮춰요');
    expect(
      text(angle(), pose(PoseHint.adjustPose, error: 0.25)),
      '포즈를 레퍼런스처럼 맞춰요 · 50%',
    );
    expect(text(angle(), pose(PoseHint.matched)), '좋아요, 그대로!');
  });
}
