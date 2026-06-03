import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/widgets/card_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/rarity.dart';

class ProductCardsScreen extends StatefulWidget {
  final String productId;
  final String? productName;
  final String? seriesName;

  const ProductCardsScreen({
    super.key,
    required this.productId,
    this.productName,
    this.seriesName,
  });

  @override
  State<ProductCardsScreen> createState() => _ProductCardsScreenState();
}

class _ProductCardsScreenState extends State<ProductCardsScreen> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCards();
  }

  /// collectionNumber('047' 등) → 정렬용 숫자. 파싱 실패 시 매우 큰 값(하단).
  int _numberKey(Map<String, dynamic> c) {
    final raw = (c['collectionNumber'] as String? ?? '').trim();
    if (raw.isEmpty) return 1 << 30;
    // 앞 0 제거 후 선두 숫자만 파싱 ('047' → 47, '012a' → 12).
    final m = RegExp(r'\d+').firstMatch(raw);
    if (m != null) {
      final n = int.tryParse(m.group(0)!);
      if (n != null) return n;
    }
    return 1 << 30;
  }

  Future<void> _loadCards() async {
    try {
      final res = await ApiClient.get('${ApiConstants.cards}/product/${widget.productId}');
      final items = res['data'] as List? ?? [];
      if (!mounted) return;
      const lowRarity = {'', 'C', 'U', 'TR'};
      final list = items
          .map((e) => Map<String, dynamic>.from(e))
          .where((c) => !lowRarity.contains(c['rarityCode'] as String? ?? ''))
          .toList()
        // 정렬: ① 고레어 우선(AppRarity.rank — 값 작을수록 고레어, UNKNOWN=99 하단)
        //       ② 같은 rarity 내 collectionNumber 오름차순
        //       ③ 번호도 같으면 이름 fallback. crash-safe.
        ..sort((a, b) {
          final ra = AppRarity.rank(a['rarityCode'] as String?);
          final rb = AppRarity.rank(b['rarityCode'] as String?);
          if (ra != rb) return ra.compareTo(rb);
          final na = _numberKey(a);
          final nb = _numberKey(b);
          if (na != nb) return na.compareTo(nb);
          final nameA = a['name'] as String? ?? '';
          final nameB = b['name'] as String? ?? '';
          return nameA.compareTo(nameB);
        });
      setState(() {
        _cards = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.productName ?? '팩 카드 목록';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: const BackButton(color: AppColors.textPrimary),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.seriesName != null && widget.seriesName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.seriesName!,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: AppColors.blue,
                  minHeight: 2,
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.textMuted))
          : _cards.isEmpty
              ? const Center(
                  child: Text(
                    '카드 정보가 없습니다',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Text(
                        '총 ${_cards.length}장',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        itemCount: _cards.length,
                        itemBuilder: (context, index) =>
                            _buildCardItem(_cards[index]),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildCardItem(Map<String, dynamic> card) {
    final cardId = card['cardId'] ?? '';
    final name = card['name'] as String? ?? '';
    final rarity = card['rarityCode'] as String? ?? '';
    final number = card['collectionNumber'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(card);

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: card),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Row(
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 48,
              height: 67,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (rarity.isNotEmpty) ...[
                        _buildRarityBadge(rarity),
                        const SizedBox(width: 8),
                      ],
                      if (number.isNotEmpty)
                        Text(
                          number,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRarityBadge(String rarity) {
    final color = AppColors.rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        rarity,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
