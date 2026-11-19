import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../models/preset.dart';
import '../providers/ad_providers.dart';
import '../providers/preset_providers.dart';
import 'native_ad_tile.dart';
import 'preset_grid_item.dart';

/// 화면 절반 높이로 올라오는 프리셋 선택 시트.
Future<void> showPresetBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const PresetBottomSheet(),
  );
}

class PresetBottomSheet extends ConsumerStatefulWidget {
  const PresetBottomSheet({super.key});

  /// 그리드에서 네이티브 광고가 들어갈 위치 (5번째 칸, PRD Step 2).
  static const adSlotIndex = 4;

  @override
  ConsumerState<PresetBottomSheet> createState() => _PresetBottomSheetState();
}

class _PresetBottomSheetState extends ConsumerState<PresetBottomSheet> {
  PresetCategory? _category;
  NativeAd? _nativeAd;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  Future<void> _loadNativeAd() async {
    // show_native_ad=false면 AdService가 즉시 null 반환 → 기본 프리셋 UI 유지.
    final ad = await ref.read(adServiceProvider).loadNativeAd();
    if (!mounted) {
      await ad?.dispose();
      return;
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
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Column(
        children: [
          const _Handle(),
          _CategoryChips(
            // 프리셋이 있는 카테고리만 칩으로 보여준다 (빈 카테고리 칩 방지)
            categories: [
              for (final c in PresetCategory.values)
                if (presets.value?.any((p) => p.category == c) ?? false) c,
            ],
            selected: _category,
            onSelected: (c) => setState(() => _category = c),
          ),
          Expanded(
            child: presets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('프리셋을 불러오지 못했어요\n$e')),
              data: (all) {
                final filtered = _category == null
                    ? all
                    : all.where((p) => p.category == _category).toList();
                final cells = _buildCells(context, filtered, selected);
                return GridView.builder(
                  controller: scrollController,
                  // 하단 내비게이션 바(제스처 바) 뒤로 칸이 숨지 않게 inset 추가
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    24 + MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 3 / 4.2,
                  ),
                  itemCount: cells.length,
                  itemBuilder: (context, i) => cells[i],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCells(
    BuildContext context,
    List<Preset> presets,
    Preset? selected,
  ) {
    final cells = <Widget>[
      CreateFromPhotoItem(
        onTap: () => ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('내 사진으로 실루엣 만들기는 곧 제공돼요'))),
      ),
      for (final preset in presets)
        PresetGridItem(
          key: ValueKey(preset.id),
          preset: preset,
          selected: preset == selected,
          onTap: () {
            ref.read(selectedPresetProvider.notifier).toggle(preset);
            Navigator.of(context).pop();
          },
        ),
    ];
    final ad = _nativeAd;
    if (ad != null && cells.length >= PresetBottomSheet.adSlotIndex) {
      cells.insert(
        PresetBottomSheet.adSlotIndex,
        NativeAdTile(key: const ValueKey('native-ad'), ad: ad),
      );
    }
    return cells;
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 10, bottom: 6),
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: Colors.white30,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<PresetCategory> categories;
  final PresetCategory? selected;
  final ValueChanged<PresetCategory?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final category in [null, ...categories])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(category?.label ?? '전체'),
                selected: selected == category,
                onSelected: (_) => onSelected(category),
              ),
            ),
        ],
      ),
    );
  }
}
