import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 로드된 네이티브 광고를 그리드 칸 크기로 표시. 광고 dispose는 소유자(시트)가 담당.
class NativeAdTile extends StatelessWidget {
  const NativeAdTile({super.key, required this.ad});

  final NativeAd ad;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: const Color(0xFF2A2A2E),
        child: Stack(
          children: [
            Positioned.fill(child: AdWidget(ad: ad)),
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('AD', style: TextStyle(fontSize: 10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
