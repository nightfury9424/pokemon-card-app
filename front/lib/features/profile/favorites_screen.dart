import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

/// 카드 단위 관심 목록 — 거래 리스트에서 하트로 찜한 카드들.
/// (이전 판매글 단위 favorites는 폐기)
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
      final res = await ApiClient.get('/api/card-interests/me');
      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeCard(String cardId) async {
    final removed = _items.firstWhere(
      (e) => e['cardId'] == cardId,
      orElse: () => const {},
    );
    setState(() => _items.removeWhere((e) => e['cardId'] == cardId));
    try {
      await ApiClient.post('/api/card-interests/$cardId/toggle', const {});
    } catch (_) {
      // 실패 시 롤백
      if (!mounted) return;
      if (removed.isNotEmpty) setState(() => _items.add(Map<String, dynamic>.from(removed)));
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
        title: const Text('관심 카드'),
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
                      const Text('관심 카드가 없습니다',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                      const SizedBox(height: 8),
                      const Text('거래 리스트에서 하트를 눌러 추가해보세요',
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
    final cardId = item['cardId'] as String? ?? '';
    final name = item['name'] as String? ?? cardId;
    final rarity = item['rarityCode'] as String? ?? '';
    final language = item['language'] as String? ?? '';
    final imageUrl = resolveCardImageUrl(item);

    return InkWell(
      onTap: () => context.push('/card/$cardId', extra: {'cardData': item}),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CardImage(
                imageUrl: imageUrl,
                width: 44,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rarity.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.rarityColor(rarity).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            rarity,
                            style: TextStyle(
                              color: AppColors.rarityColor(rarity),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      if (language.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          language,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _removeCard(cardId),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.favorite_rounded,
                  color: AppColors.red,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
