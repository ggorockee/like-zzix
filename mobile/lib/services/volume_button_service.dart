import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// 하드웨어 볼륨 버튼 촬영.
///
/// 듣는 동안만 볼륨 버튼이 셔터가 되고, 구독을 끊으면 원래 기능(음량)으로 돌아간다.
/// - Android: MainActivity가 볼륨 키를 가로챔
/// - iOS 17.2 이상: AVCaptureEventInteraction (Apple 공식 API). 그 아래 버전은 동작하지 않음
class VolumeButtonService {
  static const _channel = EventChannel('likezzix/volume_button');

  /// 버튼을 누를 때마다 이벤트. 지원하지 않는 환경(테스트 등)에서는 빈 스트림.
  Stream<void> get presses => Platform.isAndroid || Platform.isIOS
      ? _channel.receiveBroadcastStream().map((_) {})
      : const Stream<void>.empty();
}
