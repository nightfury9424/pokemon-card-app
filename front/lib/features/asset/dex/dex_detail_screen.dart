// 2026-05-29 Phase B — 도감 시리즈 상세.
//
// 구조 (사용자 명시):
//   상단: 시리즈명 + 보유율 헤더 + progress bar
//   중간: 힛카드 4장 별도 행 (rarity priority — MUR>BWR>SAR>SSR>UR>...)
//   본문: 전체 카드 3-col grid (도감 번호순)
//   보유: 컬러 / 미보유: ColorFilter.matrix grayscale
//   미보유 카드 탭 → 기존 카드 상세 (/card/:cardId)

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import 'dex_api.dart';
import 'dex_models.dart';

class DexDetailScreen extends StatefulWidget {
  final String productId;
  const DexDetailScreen({super.key, required this.productId});

  @override
  State<DexDetailScreen> createState() => _DexDetailScreenState();
}

class _DexDetailScreenState extends State<DexDetailScreen> {
  DexDetail? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final d = await DexApi.getDexDetail(widget.productId);
      if (mounted) setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '시리즈를 불러오지 못했습니다'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('도감', style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blueLight))
          : (_error != null || _data == null)
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error ?? '없음', style: const TextStyle(color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('다시 시도')),
                  ]),
                )
              : _buildContent(_data!),
    );
  }

  Widget _buildContent(DexDetail d) {
    return RefreshIndicator(
      color: AppColors.blueLight,
      backgroundColor: AppColors.surfaceCard,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _DetailHeader(data: d)),
          if (d.hits.isNotEmpty)
            SliverToBoxAdapter(child: _HitsRow(hits: d.hits)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Text('전체 카드',
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${d.cards.length}장',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.68,
                crossAxisSpacing: 8,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _DexCardTile(card: d.cards[i]),
                childCount: d.cards.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  final DexDetail data;
  const _DetailHeader({required this.data});

  @override
  Widget build(BuildContext context) {
    final ratio = data.progressRatio;
    final progressColor = ratio >= 1.0
        ? AppColors.gold
        : ratio > 0
            ? AppColors.blueLight
            : AppColors.divider;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.productName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Text('${data.ownedCount} / ${data.totalKoVisible}',
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
            const SizedBox(width: 6),
            const Text('종 보유',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const Spacer(),
            Text('${(ratio * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: progressColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                )),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.dividerSoft,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _HitsRow extends StatelessWidget {
  final List<DexCard> hits;
  const _HitsRow({required this.hits});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_fire_department, color: AppColors.gold, size: 17),
              SizedBox(width: 6),
              Text('힛카드',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          // 2026-05-29 Codex 사후 Q5 — 4분할 너무 좁아 rarity 라벨 가독성 저하.
          // horizontal scroll + 고정 width 96px → iPhone SE 에서도 4장 1.5 보이며 명확.
          SizedBox(
            height: 152,  // 96 width × 0.68 ratio ≈ 141, 라벨/badge 여백 포함.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: hits.length.clamp(0, 4),
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => SizedBox(
                width: 96,
                child: _DexCardTile(card: hits[i], hitHighlight: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DexCardTile extends StatelessWidget {
  final DexCard card;
  final bool hitHighlight;
  const _DexCardTile({required this.card, this.hitHighlight = false});

  @override
  Widget build(BuildContext context) {
    final hasImage = card.imageUrl != null && card.imageUrl!.isNotEmpty;
    // 미보유: ColorFilter.matrix grayscale.
    Widget image = hasImage
        ? CachedNetworkImage(
            imageUrl: card.imageUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => const ColoredBox(color: AppColors.surface),
            errorWidget: (_, __, ___) => const Icon(Icons.image_not_supported_outlined,
                color: AppColors.textMuted, size: 24),
          )
        : const Icon(Icons.style_outlined, color: AppColors.textMuted, size: 24);
    if (!card.owned) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0,      0,      0,      1, 0,
        ]),
        child: Opacity(opacity: 0.55, child: image),
      );
    }

    return GestureDetector(
      onTap: () => context.push('/card/${card.cardId}'),
      child: AspectRatio(
        aspectRatio: 0.68,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hitHighlight && card.owned
                  ? AppColors.gold.withOpacity(0.6)
                  : AppColors.divider,
              width: hitHighlight && card.owned ? 1.2 : 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              // rarity 라벨 (좌상단).
              if (card.rarityCode != null)
                Positioned(
                  top: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(card.rarityCode!,
                        style: TextStyle(
                          color: AppColors.rarityColor(card.rarityCode!),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        )),
                  ),
                ),
              // 보유 quantity (좌하단).
              if (card.owned && card.quantity > 1)
                Positioned(
                  bottom: 4, left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.blueDeep,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('×${card.quantity}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
