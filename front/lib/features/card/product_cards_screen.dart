import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/widgets/card_image.dart';

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

  Future<void> _loadCards() async {
    try {
      final res = await ApiClient.get('${ApiConstants.cards}/product/${widget.productId}');
      final items = res['data'] as List? ?? [];
      if (!mounted) return;
      const _lowRarity = {'', 'C', 'U', 'TR'};
      setState(() {
        _cards = items
            .map((e) => Map<String, dynamic>.from(e))
            .where((c) => !_lowRarity.contains(c['rarityCode'] as String? ?? ''))
            .toList()
          ..sort((a, b) {
            final na = a['collectionNumber'] as String? ?? '';
            final nb = b['collectionNumber'] as String? ?? '';
            return na.compareTo(nb);
          });
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
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (widget.seriesName != null)
              Text(widget.seriesName!,
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  backgroundColor: Colors.transparent,
                  color: Color(0xFF4CAF50),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white30))
          : _cards.isEmpty
              ? const Center(
                  child: Text('카드 정보가 없습니다',
                      style: TextStyle(color: Colors.white38)))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Text('총 ${_cards.length}장',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 16),
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
    final name = card['name'] ?? '';
    final rarity = card['rarityCode'] ?? '';
    final number = card['collectionNumber'] ?? '';
    final imageUrl = resolveCardImageUrl(card);

    return GestureDetector(
      onTap: () => context.push('/card/$cardId', extra: card),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF16213E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 44,
              height: 62,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rarity.isNotEmpty) ...[
                        _buildRarityBadge(rarity),
                        const SizedBox(width: 6),
                      ],
                      if (number.isNotEmpty)
                        Text(number,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildRarityBadge(String rarity) {
    final color = _rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(rarity,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Color _rarityColor(String rarity) {
    switch (rarity) {
      case 'SSR': return const Color(0xFFFF6B6B);
      case 'SAR': return const Color(0xFFFFD700);
      case 'BWR': return const Color(0xFFE8F5E9);
      case 'CSR': return const Color(0xFF00BCD4);
      case 'CHR': return const Color(0xFF4FC3F7);
      case 'UR':  return const Color(0xFF9C27B0);
      case 'SR':  return const Color(0xFF7E57C2);
      case 'AR':  return const Color(0xFFFF9800);
      default:    return Colors.white54;
    }
  }
}
