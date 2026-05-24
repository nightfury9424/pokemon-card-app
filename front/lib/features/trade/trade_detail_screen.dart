import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/widgets/auth_image.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/app_error_toast.dart';

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
  bool _statusUpdating = false;
  bool _modified = false;
  String? _myUserId;
  List<String> _tradeImages = [];
  int _currentImageIndex = 0;
  // Bundle 2-A.4: 같은 saleListingId + buyerUserId로 이미 만들어진 채팅방이 있으면
  // CTA를 "대화 중인 채팅방 보기"로 분기 + 클릭 시 기존 방으로 바로 이동.
  String? _existingChatRoomId;
  Map<String, dynamic>? _existingChatRoom;

  bool get _isSeller {
    if (_myUserId == null) return false;
    final seller = _trade?['seller'];
    if (seller is! Map) return false;
    final sellerUserId = seller['userId']?.toString();
    return sellerUserId != null && sellerUserId == _myUserId;
  }

  String get _currentTradeId {
    final tradeId = _trade?['tradeId'];
    return tradeId is String && tradeId.isNotEmpty ? tradeId : widget.tradeId;
  }

  void _popWithResult() {
    if (_modified) {
      context.pop(true);
    } else {
      context.pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTrade();
    _loadCurrentUser();
    _loadExistingChatRoom();
  }

  /// Bundle 2-A.4: 거래 상세 진입 시 GET /api/chat/rooms로 내가 보유한 채팅방 list 받아서
  /// saleListingId == widget.tradeId 인 방 찾으면 CTA 분기.
  /// (saleListingId, buyerUserId) UNIQUE라 매칭 1개 또는 0개.
  Future<void> _loadExistingChatRoom() async {
    try {
      final res = await ApiClient.get('/api/chat/rooms');
      final rooms = (res['data'] as List?) ?? [];
      Map<String, dynamic>? existing;
      for (final r in rooms) {
        if (r is Map && r['saleListingId'] == widget.tradeId) {
          existing = Map<String, dynamic>.from(r);
          break;
        }
      }
      if (existing != null && mounted) {
        setState(() {
          _existingChatRoomId = existing!['chatRoomId'] as String?;
          _existingChatRoom = existing;
        });
      }
    } catch (_) {
      // silent — 실패해도 기본 "판매자에게 문의하기" CTA로 fallback
    }
  }

  Future<void> _loadTrade() async {
    try {
      final res = await ApiClient.get('/api/trades/${widget.tradeId}');
      if (!mounted) return;
      final trade = res['data'] as Map<String, dynamic>?;
      final imageUrls = trade?['imageUrls'];
      final images = <String>[];
      if (imageUrls is List && imageUrls.isNotEmpty) {
        images.addAll(
          imageUrls
              .map((url) => url?.toString().trim() ?? '')
              .where((url) => url.isNotEmpty)
              .map(ApiConstants.tradeImageUrl),
        );
      } else {
        final imageUrl = trade?['imageUrl'];
        if (imageUrl is String && imageUrl.trim().isNotEmpty) {
          images.addAll(
            imageUrl
                .split(',')
                .map((url) => url.trim())
                .where((url) => url.isNotEmpty)
                .map(ApiConstants.tradeImageUrl),
          );
        }
      }
      setState(() {
        _trade = trade;
        _tradeImages = images;
        _currentImageIndex = 0;
        _loading = false;
      });
      _loadLikeStatus();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadLikeStatus() async {
    try {
      final res = await ApiClient.get(
        '/api/interests/${widget.tradeId}/status',
      );
      if (!mounted) return;
      final liked = res['data']?['isLiked'] as bool? ?? false;
      setState(() => _isLiked = liked);
    } catch (_) {}
  }

  Future<void> _loadCurrentUser() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      if (!mounted) return;
      final data = (res['data'] as Map<String, dynamic>?) ?? res;
      setState(() => _myUserId = data['userId']?.toString());
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_likeLoading) return;
    setState(() => _likeLoading = true);
    try {
      final res = await ApiClient.post(
        '/api/interests/${widget.tradeId}/toggle',
        {},
      );
      if (!mounted) return;
      final liked = res['data']?['isLiked'] as bool? ?? !_isLiked;
      setState(() => _isLiked = liked);
      AppSuccessToast.show(context, liked ? '관심 목록에 추가했습니다' : '관심 목록에서 제거했습니다');
    } catch (_) {
      if (mounted) {
        AppErrorToast.show(context, '오류가 발생했습니다');
      }
    } finally {
      if (mounted) setState(() => _likeLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !mounted) return;
        _popWithResult();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          elevation: 0,
          foregroundColor: AppColors.textPrimary,
          title: const Text(
            '판매글',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            if (_trade != null && _myUserId != null && !_isSeller)
              IconButton(
                tooltip: '신고하기',
                icon: const Icon(
                  Icons.flag_outlined,
                  color: AppColors.textSecondary,
                ),
                onPressed: _showReportSheet,
              ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.blue),
              )
            : _trade == null
            ? const Center(
                child: Text(
                  '판매글을 찾을 수 없습니다',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              )
            : _buildBody(),
        bottomNavigationBar: _trade != null && !_loading
            ? _buildBottomBar()
            : null,
      ),
    );
  }

  Widget _buildBody() {
    final trade = _trade!;
    final cardData =
        (trade['card'] is Map ? trade['card'] as Map<String, dynamic> : null) ??
        {};
    final seller =
        (trade['seller'] is Map
            ? trade['seller'] as Map<String, dynamic>
            : null) ??
        {};
    final title = trade['title'] ?? '';
    final description = trade['description'] ?? '';
    final price = trade['price'] as num?;
    final cardStatus = trade['cardStatus'] ?? '';
    final condition = trade['condition'] as String?;
    final conditionScore = condition != null
        ? double.tryParse(condition)
        : null;
    final gradingCompany = trade['gradingCompany'] as String?;
    final gradeValue = trade['gradeValue'] as String?;
    final createdAt = trade['createdAt'] ?? '';
    final tradeStatus = trade['status'] as String? ?? 'OPEN';
    final viewCount = (trade['viewCount'] as num?)?.toInt() ?? 0;
    final chatCount = (trade['chatCount'] as num?)?.toInt() ?? 0;
    final favoriteCount = (trade['favoriteCount'] as num?)?.toInt() ?? 0;
    final rarity = cardData['rarityCode'] ?? '';
    final cardName = cardData['name'] ?? '';
    final cardId = trade['cardId'] ?? '';
    final cardImageUrl = resolveCardImageUrl(cardData);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTradeImageSection(
            cardImageUrl,
            tradeStatus,
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 판매자 정보
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.blue.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.blue.withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: AppColors.blue,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seller['nickname'] ?? '-',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                _timeAgo(createdAt),
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                              if (viewCount > 0) ...[
                                const Text(
                                  ' · ',
                                  style: TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                                const Icon(
                                  Icons.visibility_outlined,
                                  color: AppColors.textMuted,
                                  size: 11,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '조회 $viewCount',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              if (chatCount > 0) ...[
                                const Text(' · ',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                                const Icon(Icons.chat_bubble_outline_rounded,
                                    color: AppColors.textMuted, size: 11),
                                const SizedBox(width: 2),
                                Text('채팅 $chatCount',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                              ],
                              if (favoriteCount > 0) ...[
                                const Text(' · ',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                                const Icon(Icons.favorite_border_rounded,
                                    color: AppColors.textMuted, size: 11),
                                const SizedBox(width: 2),
                                Text('관심 $favoriteCount',
                                    style: const TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: AppColors.divider),
                const SizedBox(height: 16),

                // 제목 + 가격
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                if (price != null)
                  Text(
                    AppColors.formatPrice(price.toInt()),
                    style: const TextStyle(
                      color: AppColors.green,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  const Text(
                    '가격 협의',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 18),
                  ),

                const SizedBox(height: 16),

                // 카드 정보 칩
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (rarity.isNotEmpty)
                      _buildChip(rarity, AppColors.rarityColor(rarity)),
                    _buildChip(
                      cardStatus == 'RAW' ? 'RAW' : '그레이딩',
                      AppColors.blue,
                    ),
                    if (conditionScore != null)
                      _buildChip(
                        '앱분석 ${conditionScore.toStringAsFixed(1)}점',
                        AppColors.green,
                      ),
                    if (gradingCompany != null && gradingCompany.isNotEmpty)
                      _buildChip(
                        '$gradingCompany ${gradeValue ?? ''}',
                        AppColors.gold,
                      ),
                  ],
                ),

                const SizedBox(height: 20),

                // 카드 정보 박스
                GestureDetector(
                  onTap: () async {
                    await context.push('/card/$cardId');
                  },
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
                              Text(
                                cardName,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (rarity.isNotEmpty)
                                Text(
                                  rarity,
                                  style: TextStyle(
                                    color: AppColors.rarityColor(rarity),
                                    fontSize: 11,
                                  ),
                                ),
                              const Text(
                                '카드 시세 보기',
                                style: TextStyle(
                                  color: AppColors.blue,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                if (description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.divider),
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(String ts) {
    if (ts.isEmpty) return '';
    try {
      final dt = DateTime.parse(ts);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '방금';
      if (diff.inHours < 1) return '${diff.inMinutes}분 전';
      if (diff.inDays < 1) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return ts.length >= 10 ? ts.substring(0, 10) : ts;
    }
  }

  Widget _imageFallback(
    String? cardImageUrl,
    double height,
  ) {
    return CardImage(
      imageUrl: cardImageUrl,
      width: double.infinity,
      height: height,
      fit: BoxFit.contain,
    );
  }

  Widget _buildTradeImageSection(
    String? cardImageUrl,
    String tradeStatus,
  ) {
    final hasTradeImages = _tradeImages.isNotEmpty;
    const imageHeight = 420.0;

    return Column(
      children: [
        SizedBox(
          height: imageHeight,
          child: Stack(
            children: [
              if (hasTradeImages)
                PageView.builder(
                  itemCount: _tradeImages.length,
                  onPageChanged: (index) {
                    if (!mounted) return;
                    setState(() => _currentImageIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _showFullscreenImages(index),
                      // AuthImage: /api/images/secure/** JWT 부착 (사용자 업로드 trade 이미지)
                      child: AuthImage(
                        url: _tradeImages[index],
                        width: double.infinity,
                        height: imageHeight,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _imageFallback(
                          cardImageUrl,
                          imageHeight,
                        ),
                      ),
                    );
                  },
                )
              else
                _imageFallback(cardImageUrl, imageHeight),
              if (tradeStatus != 'OPEN')
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.55),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white30),
                        ),
                        child: Text(
                          switch (tradeStatus) {
                            'RESERVED' => '예약중',
                            'DELETED' => '삭제됨',
                            _ => '거래완료',
                          },
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hasTradeImages)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_tradeImages.length, (index) {
                final selected = index == _currentImageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: selected ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.blue : AppColors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  void _showFullscreenImages(int initialIndex) {
    if (_tradeImages.isEmpty) return;
    final safeInitialIndex = initialIndex
        .clamp(0, _tradeImages.length - 1)
        .toInt();
    final controller = PageController(initialPage: safeInitialIndex);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (context) {
        return Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              PageView.builder(
                controller: controller,
                itemCount: _tradeImages.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      // AuthImage: fullscreen view (사용자 업로드 trade 이미지)
                      child: AuthImage(
                        url: _tradeImages[index],
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white54,
                          size: 56,
                        ),
                      ),
                    ),
                  );
                },
              ),
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// Bundle 2-A.5: 거래 상태 + 기존 채팅방 조합 CTA 라벨.
  /// 기존 채팅방 있으면 status 무관 "대화 이어가기".
  /// 없으면 OPEN만 신규 채팅 허용, 그 외 disabled 상태 표시.
  String _chatCtaLabel(String tradeStatus) {
    if (_existingChatRoomId != null) return '대화 이어가기';
    return switch (tradeStatus) {
      'OPEN' => '채팅하기',
      'RESERVED' => '예약 중',
      'COMPLETED' => '거래 완료',
      'DELETED' => '삭제됨',
      _ => '채팅하기',
    };
  }

  Future<void> _startChat() async {
    if (_chatLoading) return;
    // Phase 1 hotfix#2: existing 분기 제거 — 차단/상대 나감 backend 가드 우회 막음.
    // backend getOrCreateRoom 은 unique constraint 로 idempotent — existing 이면 같은 room 반환,
    // 차단/상대 나감이면 save 전 403 (BLOCKED / OTHER_LEFT). 빈 채팅방 생성 X.
    setState(() => _chatLoading = true);
    try {
      final res = await ApiClient.post('/api/chat/rooms', {
        'saleListingId': widget.tradeId,
      });
      if (!mounted) return;
      final room = res['data'] as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _existingChatRoomId = room['chatRoomId'] as String?;
          _existingChatRoom = room;
        });
      }
      await context.push('/chat/${room['chatRoomId']}', extra: room);
    } on DioException catch (e) {
      // Phase 1 hotfix#6: status + reason 분기.
      // - 410 GONE TRADE_DELETED → 안내 + 상세 닫고 hoga refresh
      // - 409 CONFLICT TRADE_RESERVED/COMPLETED → reason별 안내, 화면 유지
      // - 403 = BLOCKED/OTHER_LEFT → "연락할 수 없는 사용자입니다", 화면 유지
      // - 그 외 → 일반 실패
      if (!mounted) return;
      final status = e.response?.statusCode;
      final reason = e.response?.data is Map
          ? (e.response?.data as Map)['message'] as String?
          : null;
      if (status == 410) {
        AppErrorToast.show(context, '삭제된 판매글입니다');
        context.pop(true); // card_detail _refreshAfterOrderMutation → hoga 갱신
        return;
      }
      if (status == 409) {
        final msg = switch (reason) {
          'TRADE_RESERVED' => '예약 중인 거래입니다',
          'TRADE_COMPLETED' => '거래가 완료되었습니다',
          _ => '채팅을 시작할 수 없는 상태입니다',
        };
        AppErrorToast.show(context, msg);
        return;
      }
      final blocked = status == 403;
      AppErrorToast.show(context,
          blocked ? '연락할 수 없는 사용자입니다' : '채팅방을 열 수 없습니다');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '채팅방을 열 수 없습니다');
    } finally {
      if (mounted) setState(() => _chatLoading = false);
    }
  }

  Widget _buildBottomBar() {
    final tradeStatus = _trade?['status'] as String? ?? 'OPEN';
    // Bundle 2-A.5: 거래 상태별 CTA 게이트.
    // - 기존 채팅방 있으면 status 무관 활성 (이미 대화 중인 buyer는 계속 진행 가능)
    // - 없으면 OPEN일 때만 새 채팅 시작 가능
    // RESERVED/COMPLETED/DELETED는 새 buyer 진입 차단 (CANCELED 제거 2026-05-22 — 판매글 상태 부적합).
    final hasExistingRoom = _existingChatRoomId != null;
    final canChat = !_chatLoading && (hasExistingRoom || tradeStatus == 'OPEN');

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      child: _isSeller
          ? Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _showStatusSheet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.blue, Color(0xFF1A56B0)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sync_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '상태 변경',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _showSellerMenu,
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // 관심 버튼
                GestureDetector(
                  onTap: _toggleLike,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _isLiked
                          ? AppColors.red.withOpacity(0.12)
                          : Colors.transparent,
                      border: Border.all(
                        color: _isLiked
                            ? AppColors.red.withOpacity(0.6)
                            : AppColors.divider,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        _isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _isLiked
                            ? AppColors.red
                            : AppColors.textSecondary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 채팅하기 버튼
                Expanded(
                  child: GestureDetector(
                    onTap: canChat ? _startChat : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: canChat
                              ? [AppColors.blue, const Color(0xFF1A56B0)]
                              : [AppColors.textMuted, AppColors.textMuted],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _chatLoading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                // Bundle 2-A.5: 기존 채팅방 + 거래 상태 조합으로 CTA 분기.
                                Text(
                                  _chatCtaLabel(tradeStatus),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  void _showStatusSheet() {
    final currentStatus = _trade?['status'] as String? ?? 'OPEN';
    // 판매글 상태 정책 — OPEN / RESERVED / COMPLETED / DELETED 4개.
    // 거래 취소는 RESERVED → OPEN 복귀로 처리. 판매 종료는 DELETED (별도 삭제 흐름).
    // 이전 'CLOSED'는 'COMPLETED'로 통일 (2026-05-22).
    final options = <Map<String, dynamic>>[
      {'label': '판매중', 'status': 'OPEN', 'icon': Icons.sell_rounded},
      {'label': '예약 중', 'status': 'RESERVED', 'icon': Icons.bookmark_rounded},
      {'label': '거래 완료', 'status': 'COMPLETED', 'icon': Icons.check_circle_rounded},
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: options.map((option) {
                final label = option['label'] as String;
                final status = option['status'] as String;
                final icon = option['icon'] as IconData;
                final selected = status == currentStatus;
                final color = selected
                    ? AppColors.blue
                    : AppColors.textSecondary;
                return ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: AppColors.blue)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _updateStatus(status);
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_statusUpdating) return;
    final trade = _trade;
    if (trade == null) return;

    final oldStatus = trade['status'] as String? ?? 'OPEN';
    if (oldStatus == newStatus) return;

    setState(() {
      _statusUpdating = true;
      trade['status'] = newStatus;
    });

    try {
      await ApiClient.patch(
        '/api/trades/$_currentTradeId/status',
        data: {
          'data': {'status': newStatus},
        },
      );
      _modified = true;
    } catch (_) {
      if (!mounted) return;
      setState(() => trade['status'] = oldStatus);
      AppErrorToast.show(context, '상태 변경 실패');
    } finally {
      if (mounted) setState(() => _statusUpdating = false);
    }
  }

  void _showSellerMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.red),
              title: const Text(
                '삭제하기',
                style: TextStyle(
                  color: AppColors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _confirmDelete();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete() async {
    // Polish (2026-05-19): Material AlertDialog → AppConfirmDialog (토스 스타일)
    final ok = await AppConfirmDialog.show(
      context,
      title: '판매글 삭제',
      message: '삭제하면 되돌릴 수 없습니다.\n진행 중인 채팅에 영향을 줄 수 있습니다.',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (ok == true && mounted) {
      await _deleteTrade();
    }
  }

  void _showReportSheet() {
    const reasons = <Map<String, String>>[
      {'code': 'FRAUD', 'label': '사기 의심', 'desc': '입금 후 잠적, 허위 매물 등'},
      {'code': 'FAKE', 'label': '가품 / 위조', 'desc': '가품으로 의심되는 카드'},
      {'code': 'ABUSIVE_PRICE', 'label': '시세 교란', 'desc': '비정상적 가격으로 시장 교란'},
      {'code': 'INSULT', 'label': '욕설 / 비방', 'desc': '부적절한 언행'},
      {'code': 'SPAM', 'label': '스팸 / 광고', 'desc': '도배, 광고성 글'},
      {'code': 'OTHER', 'label': '기타', 'desc': '직접 사유 입력'},
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '신고 사유 선택',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const Divider(color: AppColors.divider, height: 1),
                ...reasons.map((r) {
                  return ListTile(
                    title: Text(
                      r['label']!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      r['desc']!,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _askReportDetail(r['code']!, r['label']!);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _askReportDetail(String reasonCode, String reasonLabel) async {
    final controller = TextEditingController();
    final detail = await showDialog<String>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceCard,
          title: Text(
            '신고: $reasonLabel',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
          ),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: '상세 내용을 입력해 주세요 (선택)',
              hintStyle: TextStyle(color: AppColors.textMuted),
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text(
                '취소',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogCtx).pop(controller.text.trim()),
              child: const Text(
                '신고 접수',
                style: TextStyle(
                  color: AppColors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (detail == null) return;
    await _submitReport(reasonCode, detail);
  }

  Future<void> _submitReport(String reasonCode, String detail) async {
    try {
      await ApiClient.post('/api/reports', {
        'data': {
          'targetType': 'TRADE',
          'targetId': _currentTradeId,
          'reason': reasonCode,
          if (detail.isNotEmpty) 'detail': detail,
        },
      });
      if (!mounted) return;
      AppSuccessToast.show(context, '신고가 접수되었어요.\n검토 후 처리할게요.');
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('이미 신고하신')
          ? '이미 신고하신 항목입니다.'
          : '신고 접수 실패. 잠시 후 다시 시도해 주세요.';
      AppErrorToast.show(context, msg);
    }
  }

  Future<void> _deleteTrade() async {
    try {
      await ApiClient.delete('/api/trades/$_currentTradeId');
      if (!mounted) return;
      // rootOverlay 사용이라 pop 후에도 토스트 유지.
      AppSuccessToast.show(context, '판매글이 삭제되었습니다');
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      AppErrorToast.show(context, '삭제 실패');
    }
  }
}
