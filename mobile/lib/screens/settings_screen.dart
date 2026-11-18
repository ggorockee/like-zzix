import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../models/account_role.dart';
import '../models/auth_session.dart';
import '../providers/auth_providers.dart';
import '../services/auth_exception.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

/// 설정 화면. 촬영 관련 옵션(무음/비율 크롭/격자선)과 정책 링크는 M5에서 추가.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider).value;
    final version = ref.watch(_packageInfoProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const _SectionHeader('계정'),
          if (session == null)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('로그인'),
              subtitle: const Text('카카오 · Google · Apple'),
              onTap: () => context.push('/settings/login'),
            )
          else
            ..._accountTiles(context, ref, session),
          const Divider(),
          ListTile(
            title: const Text('앱 버전'),
            trailing: Text(
              version == null
                  ? ''
                  : '${version.version} (${version.buildNumber})',
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _accountTiles(
    BuildContext context,
    WidgetRef ref,
    AuthSession session,
  ) {
    final user = session.user;
    final badge = switch (user.role) {
      AccountRole.superuser => '슈퍼계정 · 광고 없음',
      AccountRole.staff => '스태프 · 광고 없음',
      AccountRole.user || AccountRole.guest => null,
    };
    return [
      ListTile(
        leading: const Icon(Icons.account_circle_outlined),
        title: Text(user.displayName),
        subtitle: Text(
          [
            if (user.provider != null) '${user.provider!.label} 로그인',
            ?badge,
          ].join(' · '),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('로그아웃'),
        onTap: () => _signOut(context, ref),
      ),
      ListTile(
        leading: const Icon(Icons.person_remove_outlined),
        title: const Text('회원 탈퇴'),
        onTap: () => _deleteAccount(context, ref),
      ),
    ];
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(authSessionProvider.notifier).signOut();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('로그아웃되었습니다')));
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '계정과 연결된 정보가 삭제되며 되돌릴 수 없습니다.\n'
          '촬영한 사진은 기기 앨범에 그대로 남아 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authSessionProvider.notifier).deleteAccount();
      messenger.showSnackBar(const SnackBar(content: Text('탈퇴가 완료되었습니다')));
    } on AuthException catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('탈퇴하지 못했습니다. ${e.message}')),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
