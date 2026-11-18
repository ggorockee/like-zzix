import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_theme.dart';
import '../models/app_version.dart';
import '../services/telemetry_service.dart';

/// 스토어 업데이트 안내 팝업 (Remote Config 버전 정책).
///
/// - 강제: 닫을 수 없음. "업데이트"를 눌러 스토어로 가도 팝업은 남는다.
/// - 선택: "나중에"를 누르면 같은 최신 버전에 대해 다시 묻지 않는다.
abstract final class UpdatePrompt {
  static const _dismissedKey = 'update_dismissed_version';

  /// 필요하면 팝업을 띄운다. 강제 업데이트면 반환되지 않는다(앱 진행 차단).
  static Future<void> showIfNeeded(
    BuildContext context, {
    required UpdatePolicy policy,
    required AppVersion current,
    TelemetryService? telemetry,
    Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance,
  }) async {
    switch (policy.evaluate(current)) {
      case UpdateRequirement.none:
        return;
      case UpdateRequirement.force:
        telemetry?.record(AppEvent.forceUpdateShown);
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => PopScope(
            canPop: false,
            child: _UpdateDialog(
              forced: true,
              policy: policy,
              onUpdate: () {
                telemetry?.record(AppEvent.updateAccepted);
                _openStore(policy.storeUrl);
              },
            ),
          ),
        );
      case UpdateRequirement.optional:
        final store = await prefs();
        final latest = policy.latestVersion.toString();
        if (store.getString(_dismissedKey) == latest || !context.mounted) {
          return;
        }
        telemetry?.record(AppEvent.updatePromptShown);
        final update = await showDialog<bool>(
          context: context,
          builder: (context) => _UpdateDialog(
            forced: false,
            policy: policy,
            onUpdate: () => Navigator.pop(context, true),
            onLater: () => Navigator.pop(context, false),
          ),
        );
        if (update ?? false) {
          telemetry?.record(AppEvent.updateAccepted);
          await _openStore(policy.storeUrl);
        } else {
          telemetry?.record(AppEvent.updateDismissed);
          await store.setString(_dismissedKey, latest);
        }
    }
  }

  static Future<void> _openStore(String url) async {
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object catch (e) {
      debugPrint('[Update] 스토어 열기 실패: $e');
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.forced,
    required this.policy,
    required this.onUpdate,
    this.onLater,
  });

  final bool forced;
  final UpdatePolicy policy;
  final VoidCallback onUpdate;
  final VoidCallback? onLater;

  @override
  Widget build(BuildContext context) {
    final message = policy.message.isNotEmpty
        ? policy.message
        : forced
        ? '더 안정적인 촬영을 위해 최신 버전으로 업데이트가 필요해요.'
        : '새 버전(${policy.latestVersion})이 나왔어요. 지금 업데이트할까요?';
    return AlertDialog(
      icon: const Icon(Icons.system_update, color: AppTheme.brand, size: 36),
      title: Text(forced ? '업데이트가 필요해요' : '새 버전이 있어요'),
      content: Text(message, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        if (!forced) TextButton(onPressed: onLater, child: const Text('나중에')),
        if (policy.storeUrl.isNotEmpty)
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.brand),
            onPressed: onUpdate,
            child: const Text('업데이트'),
          ),
      ],
    );
  }
}
