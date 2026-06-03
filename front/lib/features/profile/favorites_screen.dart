import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

/// 관심 목록 — 2탭: 게시물(저장한 거래글) + 관심 카드(하트 찜한 카드).
/// 게시물 = GET /api/interests/my (PostInterest), 카드 = GET /api/card-interests/me (CardInterest).
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _cards = [];
  bool _postsLoading = true;
  bool _cardsLoading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadPosts();
    _loadCards();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    try {
      final res = await ApiClient.get('/api/interests/my');
      if (!mounted) return;
      setState(() {
        _posts = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _postsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _postsLoading = false);
    }
  }

  Future<void> _loadCards() async {
    try {
      final res = await ApiClient.get('/api/card-interests/me');
      if (!mounted) return;
      setState(() {
        _cards = List<Map<String, dynamic>>.from(res['data'] ?? []);
        _cardsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cardsLoading = false);
    }
  }

  Future<void> _unsavePost(String tradeId) async {
    final removed = _posts.firstWhere(
      (e) => e['tradeId'] == tradeId,
      orElse: () => const {},
    );
    setState(() => _posts.removeWhere((e) => e['tradeId'] == tradeId));
    try {
      await ApiClient.post('/api/interests/$tradeId/toggle', const {});
    } catch (_) {
      if (!mounted) return;
      if (removed.isNotEmpty) setState(() => _posts.add(Map<String, dynamic>.from(removed)));
    }
  }

  Future<void> _removeCard(String cardId) async {
    final removed = _cards.firstWhere(
      (e) => e['cardId'] == cardId,
      orElse: () => const {},
    );
    setState(() => _cards.removeWhere((e) => e['cardId'] == cardId));
    try {
      await ApiClient.post('/api/card-interests/$cardId/toggle', const {});
    } catch (_) {
      if (!mounted) return;
      if (removed.isNotEmpty) setState(() => _cards.add(Map<String, dynamic>.from(removed)));
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
        title: const Text('관심 목록'),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.blue,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          tabs: const [
            Tab(text: '게시물'),
            Tab(text: '관심 카드'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildPostsTab(),
          _buildCardsTab(),
        ],
      ),
    );
  }

  // ── 게시물 탭 ──
  Widget _buildPostsTab() {
    if (_postsLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.blue));
    }
    if (_posts.isEmpty) {
      return _empty(
        icon: Icons.bookmark_border_rounded,
        title: '저장한 게시물이 없습니다',
        sub: '거래글 상세에서 하트를 눌러 저장해보세요',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadPosts,
      color: AppColors.blue,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts.length,
        itemBuilder: (context, index) => _buildPostItem(_posts[index]),
      ),
    );
  }

  Widget _buildPostItem(Map<String, dynamic> item) {
    final tradeId = item['tradeId'] as String? ?? '';
    final title = item['title'] as String? ?? '';
    final price = (item['price'] as num?)?.toInt() ?? 0;
    final status = item['status'] as String? ?? 'OPEN';
    final card = item['card'] as Map<String, dynamic>? ?? const {};
    final seller = item['seller'] as Map<String, dynamic>? ?? const {};
    final nickname = seller['nickname'] as String? ?? '익명';
    final imageUrl = resolveCardImageUrl(card);

    final (badgeLabel, badgeColor) = switch (status) {
      'RESERVED' => ('예약중', AppColors.gold),
      'SOLD' || 'COMPLETED' => ('거래완료', AppColors.textMuted),
      _ => ('판매중', AppColors.green),
    };

    return InkWell(
      onTap: () async {
        await context.push<bool>('/trades/$tradeId');
        if (mounted) _loadPosts();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CardImage(imageUrl: imageUrl, width: 44, height: 60, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(badgeLabel,
                            style: TextStyle(
                                color: badgeColor, fontSize: 9.5, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('$nickname · ${_won(price)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => _unsavePost(tradeId),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.favorite_rounded, color: AppColors.red, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 관심 카드 탭 ──
  Widget _buildCardsTab() {
    if (_cardsLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.blue));
    }
    if (_cards.isEmpty) {
      return _empty(
        icon: Icons.favorite_border_rounded,
        title: '관심 카드가 없습니다',
        sub: '거래 리스트에서 하트를 눌러 추가해보세요',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadCards,
      color: AppColors.blue,
      backgroundColor: AppColors.surface,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _cards.length,
        itemBuilder: (context, index) => _buildCardItem(_cards[index]),
      ),
    );
  }

  Widget _buildCardItem(Map<String, dynamic> item) {
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
              child: CardImage(imageUrl: imageUrl, width: 44, height: 60, fit: BoxFit.cover),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2)),
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
                          child: Text(rarity,
                              style: TextStyle(
                                  color: AppColors.rarityColor(rarity),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3)),
                        ),
                      if (language.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(language,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
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
                child: Icon(Icons.favorite_rounded, color: AppColors.red, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty({required IconData icon, required String title, required String sub}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.textMuted, size: 56),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          const SizedBox(height: 8),
          Text(sub, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  String _won(int v) {
    final s = v.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '$s원';
  }
}
