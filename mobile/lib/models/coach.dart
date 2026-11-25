import 'package:flutter/material.dart';

import 'angle_state.dart';
import 'composition_fit.dart';

enum CoachTone { neutral, warning, perfect }

/// 폰을 움직이는 방법. 문구 옆에 그림으로 보여 준다.
enum PhoneMotion {
  /// 윗부분을 내 쪽으로·내 반대쪽으로 기울이기
  topToMe,
  topAway,

  /// 윗부분을 왼쪽·오른쪽으로 기울이기
  topLeft,
  topRight,

  /// 세운 채 옮기기
  up,
  down,
  left,
  right,
}

/// 촬영자에게 보여 줄 한 문장.
///
/// 문구 원칙: 누가 무엇을 어느 쪽으로 하는지 한 가지 뜻으로만 읽히게 쓴다.
/// - 폰 각도는 "폰 윗부분을 …로 기울이세요", 위치는 "옮기세요·올리세요·내리세요"
/// - "들어 주세요·숙여 주세요"처럼 각도와 높이가 헷갈리는 말은 쓰지 않는다
/// - 좌우는 찍히는 사람과 헷갈리지 않게 "화면 왼쪽·오른쪽"으로
@immutable
class CoachMessage {
  const CoachMessage(this.icon, this.text, this.tone, {this.motion});

  final IconData icon;

  /// 있으면 [icon] 대신 폰을 움직이는 그림을 보여 준다.
  final PhoneMotion? motion;
  final String text;
  final CoachTone tone;

  /// 촬영하는 순간 (인식이 멈춰 있어 구도 안내를 하지 않는다)
  static const shooting = CoachMessage(
    Icons.camera,
    '찍고 있어요. 폰을 움직이지 마세요',
    CoachTone.neutral,
  );

  /// 우선순위: 완성 → 폰 세우기 → 사람 찾기·잘림 → 거리 → 폰 각도 → 위치 → 시선.
  ///
  /// [front]는 전면 카메라. 카메라가 반대쪽을 보므로 폰을 기울일 방향이 반대다.
  static CoachMessage? of({
    required AngleGuide? angle,
    required CompositionFit? fit,
    required bool ready,
    bool front = false,
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
    CoachMessage move(PhoneMotion motion, String text) =>
        CoachMessage(Icons.smartphone, text, CoachTone.warning, motion: motion);

    if (angle != null && !angle.upright) {
      return const CoachMessage(
        Icons.stay_current_portrait,
        '폰을 똑바로 세우세요',
        CoachTone.neutral,
      );
    }
    // 프리셋을 고르기 전에는 수평만 안내
    if (fit == null) return _angle(angle, move, front);

    final steps = const ['반', '한', '두', '세', '네', '다섯'][fit.steps];
    final who = fit.who ?? '한 사람';
    switch (fit.action) {
      case CoachAction.findPerson:
        return const CoachMessage(
          Icons.person_search,
          '찍을 사람을 화면에 비추세요',
          CoachTone.neutral,
        );
      case CoachAction.findSecond:
        return warn(Icons.group, '두 사람이 모두 보이게 비추세요');
      case CoachAction.showHead:
        return move(PhoneMotion.up, '머리가 잘려요. 폰을 위로 올리세요');
      case CoachAction.showFeet:
        return warn(Icons.open_in_full, '발끝까지 보이게 뒤로 가세요');
      case CoachAction.stepBack:
        return warn(Icons.open_in_full, '뒤로 $steps 걸음 가세요');
      case CoachAction.stepCloser:
        return warn(Icons.close_fullscreen, '앞으로 $steps 걸음 가세요');
      case CoachAction.personCloser:
        return warn(Icons.person, '$who, 카메라 쪽으로 오세요');
      case CoachAction.personBack:
        return warn(Icons.person, '$who, 뒤로 물러나세요');
      default:
        break;
    }
    return _angle(angle, move, front) ??
        switch (fit.action) {
          CoachAction.moveLeft => move(PhoneMotion.left, '폰을 세운 채 왼쪽으로 옮기세요'),
          CoachAction.moveRight => move(
            PhoneMotion.right,
            '폰을 세운 채 오른쪽으로 옮기세요',
          ),
          CoachAction.raisePhone => move(PhoneMotion.up, '폰을 세운 채 위로 올리세요'),
          CoachAction.lowerPhone => move(PhoneMotion.down, '폰을 세운 채 아래로 내리세요'),
          CoachAction.personLeft => warn(Icons.arrow_back, '$who, 화면 왼쪽으로 가세요'),
          CoachAction.personRight => warn(
            Icons.arrow_forward,
            '$who, 화면 오른쪽으로 가세요',
          ),
          CoachAction.personUp => warn(Icons.north, '$who, 몸을 높이세요'),
          CoachAction.personDown => warn(Icons.south, '$who, 몸을 낮추세요'),
          CoachAction.lookLeft => warn(Icons.west, '찍히는 사람, 화살표 쪽을 보세요'),
          CoachAction.lookRight => warn(Icons.east, '찍히는 사람, 화살표 쪽을 보세요'),
          _ => const CoachMessage(
            Icons.check_circle,
            '좋아요! 그대로 멈추세요',
            CoachTone.neutral,
          ),
        };
  }

  /// 윗부분을 내 쪽으로 기울이면 후면 카메라는 위를, 전면 카메라는 아래를 본다.
  static CoachMessage? _angle(
    AngleGuide? angle,
    CoachMessage Function(PhoneMotion, String) move,
    bool front,
  ) {
    CoachMessage tilt({required bool toMe}) => toMe
        ? move(PhoneMotion.topToMe, '폰 윗부분을 내 쪽으로 기울이세요')
        : move(PhoneMotion.topAway, '폰 윗부분을 내 반대쪽으로 기울이세요');
    return switch ((angle?.tilt, angle?.level)) {
      (TiltHint.aimUp, _) => tilt(toMe: !front),
      (TiltHint.aimDown, _) => tilt(toMe: front),
      (_, LevelHint.rotateClockwise) => move(
        PhoneMotion.topRight,
        '폰 윗부분을 오른쪽으로 기울이세요',
      ),
      (_, LevelHint.rotateCounterClockwise) => move(
        PhoneMotion.topLeft,
        '폰 윗부분을 왼쪽으로 기울이세요',
      ),
      _ => null,
    };
  }
}
