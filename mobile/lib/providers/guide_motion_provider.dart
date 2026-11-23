import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/angle_state.dart';
import '../models/guide_motion.dart';
import 'attitude_providers.dart';
import 'preset_providers.dart';

/// 선택한 프리셋의 목표 각도에서 벗어난 만큼 가이드를 움직이는 값. 프리셋이 없으면 움직이지 않음.
final guideMotionProvider =
    NotifierProvider.autoDispose<GuideMotionNotifier, GuideMotion>(
      GuideMotionNotifier.new,
    );

class GuideMotionNotifier extends Notifier<GuideMotion> {
  @override
  GuideMotion build() {
    if (ref.watch(selectedPresetProvider) == null) return GuideMotion.still;
    final filter = GuideMotionFilter();
    GuideMotion next(AngleGuide? guide) => guide == null
        ? GuideMotion.still
        : filter.add(
            angleMatched: guide.matched,
            pitchError: guide.pitchError,
            rollError: guide.rollError,
            yawDeg: guide.yawDeg,
          );
    ref.listen(angleGuideProvider, (_, guide) => state = next(guide));
    return next(ref.read(angleGuideProvider));
  }
}
