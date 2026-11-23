import 'package:flutter/material.dart';

import 'angle_state.dart';
import 'subject.dart';

enum CoachTone { neutral, warning, perfect }

/// 촬영자에게 보여 줄 한 문장.
@immutable
class CoachMessage {
  const CoachMessage(this.icon, this.text, this.tone);

  final IconData icon;
  final String text;
  final CoachTone tone;

  /// 우선순위: 완성 → 폰 세우기 → 사람 찾기·잘림 → 거리 → 각도 → 좌우·높이.
  static CoachMessage? of({
    required AngleGuide? angle,
    required SubjectFit? fit,
    required bool ready,
  }) {
    if (ready) {
      return const CoachMessage(
        Icons.photo_camera,
        '완벽해요! 지금 찍으세요',
        CoachTone.perfect,
      );
    }
    CoachMessage warn(IconData icon, String text) =>
        CoachMessage(icon, text, CoachTone.warning);

    if (angle != null && !angle.upright) {
      return const CoachMessage(
        Icons.stay_current_portrait,
        '폰을 세워서 들어 주세요',
        CoachTone.neutral,
      );
    }
    // 프리셋을 고르기 전에는 수평만 안내
    if (fit == null) return _angle(angle, warn);

    String walk(String direction) => fit.steps == 0
        ? '조금만 $direction 가세요'
        : '$direction ${const ['', '한', '두', '세', '네', '다섯'][fit.steps]} 걸음';

    switch (fit.action) {
      case CoachAction.findPerson:
        return const CoachMessage(
          Icons.person_search,
          '사람을 화면에 담아 주세요',
          CoachTone.neutral,
        );
      case CoachAction.showHead:
        return warn(Icons.vertical_align_top, '머리가 잘려요, 폰을 살짝 들어 주세요');
      case CoachAction.showFeet:
        return warn(Icons.open_in_full, '발끝까지 나오게 뒤로 가세요');
      case CoachAction.stepBack:
        return warn(Icons.open_in_full, walk('뒤로'));
      case CoachAction.stepCloser:
        return warn(Icons.close_fullscreen, walk('앞으로'));
      default:
        break;
    }
    return _angle(angle, warn) ??
        switch (fit.action) {
          CoachAction.panLeft => warn(Icons.arrow_back, '폰을 왼쪽으로 살짝'),
          CoachAction.panRight => warn(Icons.arrow_forward, '폰을 오른쪽으로 살짝'),
          CoachAction.raisePhone => warn(Icons.north, '폰 높이를 조금 올려 주세요'),
          CoachAction.lowerPhone => warn(Icons.south, '폰 높이를 조금 낮춰 주세요'),
          _ => const CoachMessage(
            Icons.check_circle,
            '좋아요, 그대로!',
            CoachTone.neutral,
          ),
        };
  }

  static CoachMessage? _angle(
    AngleGuide? angle,
    CoachMessage Function(IconData, String) warn,
  ) => switch ((angle?.tilt, angle?.level)) {
    (TiltHint.aimUp, _) => warn(Icons.arrow_upward, '폰을 살짝 들어 주세요'),
    (TiltHint.aimDown, _) => warn(Icons.arrow_downward, '폰을 살짝 숙여 주세요'),
    (_, LevelHint.rotateClockwise) => warn(Icons.rotate_right, '폰을 시계 방향으로 살짝'),
    (_, LevelHint.rotateCounterClockwise) => warn(
      Icons.rotate_left,
      '폰을 반시계 방향으로 살짝',
    ),
    _ => null,
  };
}
