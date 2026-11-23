import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/app_theme.dart';
import '../models/preset.dart';
import '../providers/ad_providers.dart';
import '../providers/api_providers.dart';
import '../providers/preset_providers.dart';
import '../services/telemetry_service.dart';
import 'composition_card.dart';
import 'native_ad_tile.dart';

/// 화면 절반 이상 올라오는 구도 선택 시트.
Future<void> showPresetBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.ink,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const PresetBottomSheet(),
  );
}

class PresetBottomSheet extends ConsumerStatefulWidget {
  const PresetBottomSheet({super.key});

  /// 네이티브 광고 앞에 놓이는 카드 수
  static const adAfterCards = 4;

  @override
  ConsumerState<PresetBottomSheet> createState() => _PresetBottomSheetState();
}

class _PresetBottomSheetState extends ConsumerState<PresetBottomSheet> {
  /// 지금 고른 구도가 있으면 그 탭부터 보여 준다.
  late PresetCategory _category =
      ref.read(selectedPresetProvider)?.category ?? PresetCategory.basic;
  NativeAd? _nativeAd;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  Future<void> _loadNativeAd() async {
    // show_native_ad=false면 AdService가 즉시 null 반환 → 기본 목록 유지.
    final ad = await ref.read(adServiceProvider).loadNativeAd();
    if (!mounted) {
      await ad?.dispose();
      return;
    }
    if (ad != null) {
      ref.read(telemetryProvider)?.record(AppEvent.adNativeShown);
    }
    setState(() => _nativeAd = ad);
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presets = ref.watch(presetsProvider);
    final selected = ref.watch(selectedPresetProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Column(
        children: [
          const _Handle(),
          _CategoryTabs(
            selected: _category,
            onSelected: (c) => setState(() => _category = c),
          ),
          Expanded(
            child: presets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => const Center(child: Text('구도를 불러오지 못했어요')),
              data: (all) {
                final items = [
                  for (final p in all)
                    if (p.category == _category) p,
                ];
                final ad = _nativeAd;
                // 카드 4장 뒤(모자라면 끝)에 광고 한 줄
                final split = ad == null
                    ? items.length
                    : math.min(PresetBottomSheet.adAfterCards, items.length);
                return CustomScrollView(
                  controller: scrollController,
                  slivers: [
                    _grid(context, items.sublist(0, split), selected),
                    if (ad != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                        sliver: SliverToBoxAdapter(child: NativeAdTile(ad: ad)),
                      ),
                    if (split < items.length)
                      _grid(context, items.sublist(split), selected),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        // 하단 내비게이션 바(제스처 바) 뒤로 숨지 않게
                        height: 24 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, List<Preset> items, Preset? selected) =>
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            // 큰 글자에서는 글자 줄만큼 칸을 늘린다
            mainAxisExtent: 118 + MediaQuery.textScalerOf(context).scale(46),
          ),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final preset = items[i];
            return CompositionCard(
              key: ValueKey(preset.id),
              preset: preset,
              selected: preset == selected,
              onTap: () {
                ref.read(selectedPresetProvider.notifier).toggle(preset);
                Navigator.of(context).pop();
              },
            );
          },
        ),
      );
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: AppTheme.whiteFaint,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _CategoryTabs extends StatelessWidget {
  const _CategoryTabs({required this.selected, required this.onSelected});

  final PresetCategory selected;
  final ValueChanged<PresetCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final c in PresetCategory.values)
            Expanded(
              child: Semantics(
                selected: c == selected,
                button: true,
                child: InkWell(
                  onTap: () => onSelected(c),
                  child: Container(
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: c == selected
                              ? AppTheme.coral
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        c.label,
                        style: TextStyle(
                          color: c == selected
                              ? AppTheme.white
                              : AppTheme.whiteMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
