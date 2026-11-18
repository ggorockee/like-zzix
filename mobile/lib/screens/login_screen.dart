import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/sns_provider.dart';
import '../providers/auth_providers.dart';
import '../services/auth_exception.dart';

/// SNS 로그인 (선택 사항). 로그인하지 않아도 촬영 기능은 모두 사용 가능.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  SnsProvider? _inProgress;

  Future<void> _signIn(SnsProvider provider) async {
    if (_inProgress != null) return;
    setState(() => _inProgress = provider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(authSessionProvider.notifier).signIn(provider);
      if (!mounted) return;
      final user = ref.read(authSessionProvider).value?.user;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            user != null && user.role.isAdFree
                ? '${user.displayName}님, 광고 없이 이용하실 수 있어요'
                : '로그인되었습니다',
          ),
        ),
      );
      context.pop();
    } on AuthException catch (e) {
      debugPrint('[Login] $e');
      if (e.failure != AuthFailure.cancelled) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _inProgress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(snsSignInProvider).availableProviders;

    return Scaffold(
      appBar: AppBar(title: const Text('로그인')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              '로그인은 선택 사항이에요.\n로그인하지 않아도 모든 촬영 기능을 쓸 수 있어요.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 32),
            if (providers.isEmpty)
              const Text('이 빌드에는 로그인 설정이 없습니다.')
            else
              for (final provider in providers) ...[
                _SnsButton(
                  provider: provider,
                  loading: _inProgress == provider,
                  onPressed: _inProgress == null
                      ? () => _signIn(provider)
                      : null,
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _SnsButton extends StatelessWidget {
  const _SnsButton({
    required this.provider,
    required this.loading,
    required this.onPressed,
  });

  final SnsProvider provider;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // 각 사 브랜드 가이드의 기본 배경/글자색.
    final (background, foreground) = switch (provider) {
      SnsProvider.kakao => (const Color(0xFFFEE500), const Color(0xD9000000)),
      SnsProvider.google => (Colors.white, const Color(0xFF1F1F1F)),
      SnsProvider.apple => (Colors.white, Colors.black),
    };

    return SizedBox(
      height: 52,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        child: loading
            ? SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Text('${provider.label}로 계속하기'),
      ),
    );
  }
}
