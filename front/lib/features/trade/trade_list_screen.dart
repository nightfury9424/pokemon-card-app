import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class TradeListScreen extends StatefulWidget {
  final String? filterCardId;
  final String? filterCardName;
  final String? filterSellerId;
  final String? title;

  const TradeListScreen({
    super.key,
    this.filterCardId,
    this.filterCardName,
    this.filterSellerId,
    this.title,
  });

  @override
  State<TradeListScreen> createState() => _TradeListScreenState();
}

class _TradeListScreenState extends State<TradeListScreen> {
  List<Map<String, dynamic>> _trades = [];
  bool _loading = true;
  int _page = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadTrades();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200
        && _hasMore && !_loadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadTrades() async {
    try {
      final params = <String, dynamic>{'page': 0, 'size': 20};
      if (widget.filterCardId != null) params['cardId'] = widget.filterCardId;
      if (widget.filterSellerId != null) params['sellerId'] = widget.filterSellerId;
      final res = await ApiClient.get('/api/trades', params: params);
      final data = res['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _trades = List<Map<String, dynamic>>.from(data?['content'] ?? []);
        _hasMore = !(data?['last'] as bool? ?? true);
        _page = 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final params = <String, dynamic>{'page': _page + 1, 'size': 20};
      if (widget.filterCardId != null) params['cardId'] = widget.filterCardId;
      if (widget.filterSellerId != null) params['sellerId'] = widget.filterSellerId;
      final res = await ApiClient.get('/api/trades', params: params);
      final data = res['data'] as Map<String, dynamic>?;
      if (!mounted) return;
      final more = List<Map<String, dynamic>>.from(data?['content'] ?? []);
      setState(() {
        _trades.addAll(more);
        _hasMore = !(data?['last'] as bool? ?? true);
        _page++;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(
          widget.title ?? (widget.filterCardName != null ? '${widget.filterCardName} 판매 글' : '판매 중인 카드'),
          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.textSecondary),
            onPressed: () {},
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _trades.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.storefront_outlined, color: AppColors.textMuted, size: 56),
                      SizedBox(height: 16),
                      Text('등록된 판매 카드가 없습니다',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadTrades,
                  color: AppColors.blue,
                  backgroundColor: AppColors.surface,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _trades.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == _trades.length) {
                        return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(color: AppColors.blue),
                            ));
                      }
                      return _buildTradeCard(_trades[i]);
                    },
                  ),
                ),
    );
  }

  Widget _buildTradeCard(Map<String, dynamic> trade) {
    final tradeId = trade['tradeId'] ?? '';
    final cardId = trade['cardId'] ?? '';
    final title = trade['title'] ?? '';
    final price = trade['price'] as num?;
    final cardData = trade['card'] as Map<String, dynamic>? ?? {};
    final rarity = cardData['rarityCode'] ?? '';
    final imageUrl = resolveCardImageUrl(cardData);
    final sellerNickname = (trade['seller'] as Map<String, dynamic>?)?['nickname'] ?? '';
    final createdAt = trade['createdAt'] ?? '';

    return GestureDetector(
      onTap: () => context.push('/trades/$tradeId'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            CardImage(
              imageUrl: imageUrl,
              width: 80,
              height: 100,
              fit: BoxFit.cover,
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    if (rarity.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.rarityColor(rarity).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.rarityColor(rarity).withOpacity(0.4)),
                        ),
                        child: Text(rarity,
                            style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(height: 8),
                    if (price != null)
                      Text(AppColors.formatPrice(price.toInt()),
                          style: const TextStyle(color: AppColors.green, fontSize: 15, fontWeight: FontWeight.bold))
                    else
                      const Text('가격 협의', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (sellerNickname.isNotEmpty) ...[
                          const Icon(Icons.person_outline, color: AppColors.textMuted, size: 12),
                          const SizedBox(width: 3),
                          Text(sellerNickname,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          const SizedBox(width: 8),
                        ],
                        if (createdAt.isNotEmpty)
                          Text(createdAt.length > 10 ? createdAt.substring(0, 10) : createdAt,
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
