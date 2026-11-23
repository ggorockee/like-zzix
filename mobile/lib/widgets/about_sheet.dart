import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../providers/ad_providers.dart';
import '../services/ad_consent_service.dart';

/// 앱 정보: 개인정보처리방침·고객지원·오픈소스 라이선스·버전.
Future<void> showAboutSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: AppTheme.ink,
  isScrollControlled: true,
  builder: (context) => const AboutSheet(),
);

class AboutSheet extends ConsumerWidget {
  const AboutSheet({super.key});

  /// 정책 페이지는 앱 설정과 무관하게 항상 열려야 하므로 고정 주소를 쓴다.
  static const privacyUrl = 'https://like-zzix.woohalabs.com/privacy';
  static const supportUrl = 'https://like-zzix.woohalabs.com/support';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version =
        ref.watch(appInitProvider).value?.currentVersion.toString() ?? '';
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('라익찍스', style: Theme.of(context).textTheme.titleLarge),
            if (version.isNotEmpty)
              Text(
                '버전 $version',
                style: const TextStyle(color: AppTheme.whiteMuted),
              ),
            const SizedBox(height: 8),
            _Item(
              icon: Icons.privacy_tip_outlined,
              title: '개인정보처리방침',
              onTap: () => _open(privacyUrl),
            ),
            _Item(
              icon: Icons.help_outline,
              title: '고객지원·문의',
              onTap: () => _open(supportUrl),
            ),
            const _AdPrivacyItem(),
            _Item(
              icon: Icons.description_outlined,
              title: '오픈소스 라이선스',
              onTap: () => showLicensePage(
                context: context,
                applicationName: '라익찍스',
                applicationVersion: version,
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Text(
                '카메라 영상과 얼굴·자세 인식은 기기 안에서만 처리되고 서버로 보내지 않아요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppTheme.whiteMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      debugPrint('[About] 링크 열기 실패: $e');
    }
  }
}

/// 광고 동의를 바꿀 수 있어야 하는 지역에서만 보인다.
class _AdPrivacyItem extends StatefulWidget {
  const _AdPrivacyItem();

  @override
  State<_AdPrivacyItem> createState() => _AdPrivacyItemState();
}

class _AdPrivacyItemState extends State<_AdPrivacyItem> {
  late final Future<bool> _required = AdConsentService.privacyOptionsRequired();

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _required,
    builder: (context, snapshot) => snapshot.data ?? false
        ? const _Item(
            icon: Icons.tune,
            title: '광고 개인정보 설정',
            onTap: AdConsentService.showPrivacyOptions,
          )
        : const SizedBox.shrink(),
  );
}

class _Item extends StatelessWidget {
  const _Item({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppTheme.whiteMuted),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right, color: AppTheme.whiteFaint),
    onTap: onTap,
  );
}
