import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<dynamic> _rooms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      final res = await ApiClient.get('/api/chat/rooms');
      setState(() {
        _rooms = res['data'] ?? [];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('채팅'),
      ),
      body: Column(
        children: [
          Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _rooms.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadRooms,
                  color: AppColors.blue,
                  backgroundColor: AppColors.surfaceCard,
                  child: ListView.separated(
                    itemCount: _rooms.length,
                    separatorBuilder: (_, __) =>
                        const Divider(color: AppColors.divider, height: 1),
                    itemBuilder: (context, i) => _buildRoomTile(_rooms[i]),
                  ),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline_rounded,
              color: AppColors.textMuted, size: 56),
          SizedBox(height: 16),
          Text('진행 중인 채팅이 없습니다',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 15)),
          SizedBox(height: 8),
          Text('판매 중인 카드에 채팅을 걸어보세요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildRoomTile(Map<String, dynamic> room) {
    final unread = (room['unreadCount'] ?? 0) as int;
    final lastMsg = room['lastMessage'] as String?;
    final otherNickname = room['otherUserNickname'] ?? '';
    final profileUrl = room['otherUserProfileImageUrl'] as String?;
    final tradeTitle = (room['tradeTitle'] as String?) ?? '';
    // Bundle 2-A.1: 채팅 목록에서 어느 거래 채팅인지 즉시 인지하도록 trade summary line 추가.
    // trade 매칭 없는 채팅방(dummy/삭제)은 row 생략 — 기존 동작 일관.
    final cardImageUrl = room['cardImageUrl'] as String?;
    final tradePrice = (room['tradePrice'] as num?)?.toInt();
    final tradeStatus = room['tradeStatus'] as String?;
    final showTradeRow = cardImageUrl != null && tradeTitle.isNotEmpty;

    return InkWell(
      onTap: () => context.push('/chat/${room['chatRoomId']}', extra: room),
      child: Padding(
        // UI polish: vertical 14→12 (밀도 ↑)
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.surfaceElevated,
              backgroundImage:
                  profileUrl != null ? NetworkImage(profileUrl) : null,
              child: profileUrl == null
                  ? const Icon(Icons.person,
                      color: AppColors.textMuted, size: 22)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(otherNickname,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: unread > 0
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        _timeAgo(room['lastMessageAt'] ?? room['createdAt']),
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastMsg ?? tradeTitle,
                    style: TextStyle(
                      color: unread > 0
                          ? AppColors.textSecondary
                          : AppColors.textMuted,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  // Bundle 2-A.1 trade summary — 썸네일 20x28 + 카드명·가격·상태 inline
                  if (showTradeRow) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CardImage(
                          imageUrl: cardImageUrl,
                          width: 20,
                          height: 28,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 11,
                              ),
                              children: [
                                TextSpan(text: tradeTitle),
                                if (tradePrice != null)
                                  TextSpan(text: ' · ${_formatPrice(tradePrice)}원'),
                                if (tradeStatus != null) ...[
                                  const TextSpan(text: ' · '),
                                  TextSpan(
                                    text: _statusLabel(tradeStatus),
                                    style: TextStyle(
                                      color: _statusColor(tradeStatus),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bundle 2-A.1: 콤마 포맷 (반올림 X) — chat_room의 동일 helper와 정책 일관.
  String _formatPrice(int price) {
    final str = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  String _statusLabel(String status) => switch (status) {
        'OPEN' => '판매중',
        'RESERVED' => '예약중',
        'COMPLETED' => '거래완료',
        'CANCELED' => '취소',
        _ => status,
      };

  /// 채팅 미니카드와 동일 — 양 빨강/음 파랑 정책 회피.
  Color _statusColor(String status) => switch (status) {
        'OPEN' => AppColors.green,
        'RESERVED' => AppColors.gold,
        'COMPLETED' => AppColors.textMuted,
        'CANCELED' => AppColors.textMuted,
        _ => AppColors.textMuted,
      };

  String _timeAgo(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts.toString());
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return '방금';
      if (diff.inHours < 1) return '${diff.inMinutes}분 전';
      if (diff.inDays < 1) return '${diff.inHours}시간 전';
      if (diff.inDays < 7) return '${diff.inDays}일 전';
      return '${dt.month}/${dt.day}';
    } catch (_) {
      return '';
    }
  }
}
