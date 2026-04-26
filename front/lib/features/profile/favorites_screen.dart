import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/interests/my');
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('관심 목록',
            style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.favorite_border_rounded, color: AppColors.textMuted, size: 56),
                      const SizedBox(height: 16),
                      const Text('관심 목록이 비어 있습니다',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                      const SizedBox(height: 8),
                      const Text('판매 글에서 ♡를 눌러 추가해보세요',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.blue,
                  backgroundColor: AppColors.surface,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _items.length,
                    itemBuilder: (context, index) => _buildItem(_items[index]),
                  ),
                ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final tradeId = item['tradeId'] as String? ?? '';
    final title = item['title'] as String? ?? '';
    final price = item['price'] as num?;
    final status = item['status'] as String? ?? 'OPEN';
    final cardStatus = item['cardStatus'] as String? ?? 'RAW';
    final card = item['card'] as Map<String, dynamic>? ?? {};
    final cardId = card['cardId'] as String? ?? '';
    final cardName = card['name'] as String? ?? '';
    final rarity = card['rarityCode'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(card);
    final seller = item['seller'] as Map<String, dynamic>? ?? {};
    final sellerNick = seller['nickname'] as String? ?? '';

    final isSold = status == 'SOLD';
    final glowColor = AppColors.rarityGlow(rarity);
    final hasGlow = rarity.isNotEmpty && glowColor != Colors.transparent;

    return GestureDetector(
      onTap: () => context.push('/trades/$tradeId'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            // 카드 이미지
            Container(
              width: 44,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: hasGlow ? glowColor.withOpacity(0.5) : AppColors.divider,
                  width: hasGlow ? 1.5 : 1,
                ),
              ),
              child: CardImage(
                imageUrl: imageUrl,
                width: 44,
                height: 62,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 14),
            // 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rarity.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.rarityColor(rarity).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(rarity,
                              style: TextStyle(
                                  color: AppColors.rarityColor(rarity),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(cardStatus,
                          style: const TextStyle(
                              color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 6),
                      Text(sellerNick,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            // 가격 + 상태
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (price != null && price > 0)
                  Text(
                    AppColors.formatPrice(price.toInt()),
                    style: TextStyle(
                      color: isSold ? AppColors.textMuted : AppColors.green,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: isSold ? TextDecoration.lineThrough : null,
                    ),
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _statusColor(status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                        color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'OPEN': return '판매중';
      case 'RESERVED': return '예약중';
      case 'SOLD': return '판매완료';
      default: return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'OPEN': return AppColors.green;
      case 'RESERVED': return AppColors.gold;
      case 'SOLD': return AppColors.textMuted;
      default: return AppColors.textMuted;
    }
  }
}
