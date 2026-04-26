import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class TradeDetailScreen extends StatefulWidget {
  final String tradeId;

  const TradeDetailScreen({super.key, required this.tradeId});

  @override
  State<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

class _TradeDetailScreenState extends State<TradeDetailScreen> {
  Map<String, dynamic>? _trade;
  bool _loading = true;
  bool _isLiked = false;
  bool _likeLoading = false;
  bool _chatLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTrade();
  }

  Future<void> _loadTrade() async {
    try {
      final res = await ApiClient.get('/api/trades/${widget.tradeId}');
      if (!mounted) return;
      setState(() {
        _trade = res['data'] as Map<String, dynamic>?;
        _loading = false;
      });
      _loadLikeStatus();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLikeStatus() async {
    try {
      final res = await ApiClient.get('/api/interests/${widget.tradeId}/status');
      if (!mounted) return;
      final liked = res['data']?['isLiked'] as bool? ?? false;
      setState(() => _isLiked = liked);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;
    setState(() => _likeLoading = true);
    try {
      final res = await ApiClient.post('/api/interests/${widget.tradeId}/toggle', {});
      if (!mounted) return;
      final liked = res['data']?['isLiked'] as bool? ?? !_isLiked;
      setState(() => _isLiked = liked);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(liked ? '관심 목록에 추가했습니다' : '관심 목록에서 제거했습니다'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오류가 발생했습니다'), duration: Duration(seconds: 1)),
        );
      }
    } finally {
      if (mounted) setState(() => _likeLoading = false);
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
        title: const Text('판매글', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _trade == null
              ? const Center(child: Text('판매글을 찾을 수 없습니다', style: TextStyle(color: AppColors.textSecondary)))
              : _buildBody(),
      bottomNavigationBar: _trade != null && !_loading ? _buildBottomBar() : null,
    );
  }

  Widget _buildBody() {
    final trade = _trade!;
    final cardData = trade['card'] as Map<String, dynamic>? ?? {};
    final seller = trade['seller'] as Map<String, dynamic>? ?? {};
    final imageUrl = trade['imageUrl'] as String?;
    final title = trade['title'] ?? '';
    final description = trade['description'] ?? '';
    final price = trade['price'] as num?;
    final cardStatus = trade['cardStatus'] ?? '';
    final gradingCompany = trade['gradingCompany'] as String?;
    final gradeValue = trade['gradeValue'] as String?;
    final createdAt = trade['createdAt'] ?? '';
    final rarity = cardData['rarityCode'] ?? '';
    final cardName = cardData['name'] ?? '';
    final cardId = trade['cardId'] ?? '';
    final cardImageUrl = resolveCardImageUrl(cardData);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 실물 사진 (판매자가 찍은 사진)
          if (imageUrl != null && imageUrl.isNotEmpty)
            Image.network(
              ApiConstants.tradeImageUrl(imageUrl),
              width: double.infinity,
              height: 300,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _imageFallback(cardImageUrl, 300),
            )
          else
            _imageFallback(cardImageUrl, 300),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 판매자 정보
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.blue.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.person, color: AppColors.blue, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(seller['nickname'] ?? '-',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(createdAt, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 16),

                // 제목 + 가격
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (price != null)
                  Text(AppColors.formatPrice(price.toInt()),
                      style: const TextStyle(color: AppColors.green, fontSize: 22, fontWeight: FontWeight.bold))
                else
                  const Text('가격 협의', style: TextStyle(color: AppColors.textMuted, fontSize: 18)),

                const SizedBox(height: 16),

                // 카드 정보 칩
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (rarity.isNotEmpty)
                      _buildChip(rarity, AppColors.rarityColor(rarity)),
                    _buildChip(cardStatus == 'RAW' ? 'RAW' : '그레이딩', AppColors.blue),
                    if (gradingCompany != null && gradingCompany.isNotEmpty)
                      _buildChip('$gradingCompany ${gradeValue ?? ''}', AppColors.gold),
                  ],
                ),

                const SizedBox(height: 20),

                // 카드 정보 박스
                GestureDetector(
                  onTap: () => context.push('/card/$cardId'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        CardImage(
                          imageUrl: cardImageUrl,
                          width: 44,
                          height: 60,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cardName,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                              if (rarity.isNotEmpty)
                                Text(rarity, style: TextStyle(color: AppColors.rarityColor(rarity), fontSize: 11)),
                              const Text('카드 시세 보기', style: TextStyle(color: AppColors.blue, fontSize: 11)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
                      ],
                    ),
                  ),
                ),

                if (description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.divider),
                  const SizedBox(height: 16),
                  Text(description,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.6)),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageFallback(String? cardImageUrl, double height) {
    return CardImage(
      imageUrl: cardImageUrl,
      width: double.infinity,
      height: height,
      fit: BoxFit.contain,
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _startChat() async {
    if (_chatLoading) return;
    setState(() => _chatLoading = true);
    try {
      final res = await ApiClient.post('/api/chat/rooms', {
        'saleListingId': widget.tradeId,
      });
      if (!mounted) return;
      final room = res['data'] as Map<String, dynamic>;
      context.push('/chat/${room['chatRoomId']}', extra: room);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('채팅방을 열 수 없습니다'), duration: Duration(seconds: 2)),
        );
      }
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: Row(
        children: [
          // 관심 버튼
          GestureDetector(
            onTap: _toggleLike,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: _isLiked ? AppColors.red.withOpacity(0.12) : Colors.transparent,
                border: Border.all(
                  color: _isLiked ? AppColors.red.withOpacity(0.6) : AppColors.divider,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: _isLiked ? AppColors.red : AppColors.textSecondary,
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 채팅하기 버튼
          Expanded(
            child: GestureDetector(
              onTap: _startChat,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _chatLoading
                        ? [AppColors.textMuted, AppColors.textMuted]
                        : [AppColors.blue, const Color(0xFF1A56B0)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _chatLoading
                    ? const Center(
                        child: SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('채팅하기', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
