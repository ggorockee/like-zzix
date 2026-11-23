import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 구도 목록 사이에 한 줄로 들어가는 네이티브 광고 (템플릿에 광고 표시가 포함됨).
/// 광고 dispose는 소유자(시트)가 담당.
class NativeAdTile extends StatelessWidget {
  const NativeAdTile({super.key, required this.ad});

  /// 작은 템플릿 권장 높이
  static const height = 100.0;

  final NativeAd ad;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AdWidget(ad: ad),
    ),
  );
}
