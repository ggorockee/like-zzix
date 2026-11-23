import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 광고 요청 전 사용자 동의 흐름: Google UMP(EEA/UK 등) → iOS ATT.
///
/// UI가 화면에 떠 있는 상태(첫 프레임 이후)에서만 호출해야 함.
class AdConsentService {
  /// 동의 절차를 진행하고 광고 요청 가능 여부를 반환.
  Future<bool> gatherConsent() async {
    await _requestUmpConsent();
    if (Platform.isIOS) {
      await _requestTrackingAuthorization();
    }
    return ConsentInformation.instance.canRequestAds();
  }

  Future<void> _requestUmpConsent() {
    final completer = Completer<void>();
    void done([FormError? error]) {
      if (error != null) {
        debugPrint('[UMP] ${error.errorCode}: ${error.message}');
      }
      if (!completer.isCompleted) completer.complete();
    }

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () => ConsentForm.loadAndShowConsentFormIfRequired(done),
      done,
    );
    return completer.future;
  }

  Future<void> _requestTrackingAuthorization() async {
    final status = await AppTrackingTransparency.trackingAuthorizationStatus;
    if (status == TrackingStatus.notDetermined) {
      await AppTrackingTransparency.requestTrackingAuthorization();
    }
  }

  /// 광고 동의를 다시 바꿀 수 있어야 하는 지역(EEA 등)인지. 정보 화면에서 메뉴를 보여 줄 때 쓴다.
  static Future<bool> privacyOptionsRequired() async {
    try {
      return await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } on Object catch (e) {
      debugPrint('[UMP] 상태 확인 실패: $e');
      return false;
    }
  }

  static Future<void> showPrivacyOptions() =>
      ConsentForm.showPrivacyOptionsForm((_) {});
}
