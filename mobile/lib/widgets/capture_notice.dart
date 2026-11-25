import 'dart:async';

import 'package:flutter/material.dart';

import '../core/app_theme.dart';

/// 촬영 결과 알림 한 건.
@immutable
class CaptureNotice {
  const CaptureNotice(this.text, {this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// 촬영 결과를 뷰파인더 맨 위에 잠깐 보여 준다.
///
/// 아래쪽 구도 안내 문구·배율·셔터를 가리지 않도록 스낵바 대신 쓴다.
/// 새 알림이 오면 이전 알림을 바로 바꾸고, [duration] 뒤에 스스로 사라진다.
class CaptureNoticeBar extends StatefulWidget {
  const CaptureNoticeBar({super.key, required this.notice});

  final ValueNotifier<CaptureNotice?> notice;

  static const duration = Duration(seconds: 3);

  @override
  State<CaptureNoticeBar> createState() => _CaptureNoticeBarState();
}

class _CaptureNoticeBarState extends State<CaptureNoticeBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.notice.addListener(_restart);
    _restart();
  }

  @override
  void dispose() {
    widget.notice.removeListener(_restart);
    _timer?.cancel();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (widget.notice.value == null) return;
    _timer = Timer(CaptureNoticeBar.duration, () => widget.notice.value = null);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.notice,
    builder: (_, notice, _) => AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: notice == null ? const SizedBox.shrink() : _bar(notice),
    ),
  );

  Widget _bar(CaptureNotice notice) => Container(
    key: ObjectKey(notice),
    padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
    constraints: const BoxConstraints(minHeight: 40),
    decoration: BoxDecoration(
      color: AppTheme.scrimStrong,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Semantics(liveRegion: true, child: Text(notice.text))),
        if (notice.actionLabel case final label?)
          TextButton(
            onPressed: () {
              widget.notice.value = null;
              notice.onAction?.call();
            },
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.coral,
              minimumSize: const Size(48, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(label),
          )
        else
          const SizedBox(width: 8),
      ],
    ),
  );
}
