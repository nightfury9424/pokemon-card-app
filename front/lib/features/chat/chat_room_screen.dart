import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/card_image.dart';

class ChatRoomScreen extends StatefulWidget {
  final String roomId;
  final Map<String, dynamic> roomInfo;

  const ChatRoomScreen({
    super.key,
    required this.roomId,
    required this.roomInfo,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  StompClient? _stompClient;
  String? _myUserId;
  bool _loading = true;
  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await TokenStorage.get();
    if (token != null) _myUserId = _userIdFromToken(token);
    await _loadMessages();
    _connectWebSocket();
  }

  String? _userIdFromToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      return map['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMessages() async {
    try {
      final res = await ApiClient.get('/api/chat/rooms/${widget.roomId}/messages');
      if (!mounted) return;
      final list = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _messages.addAll(list);
        _loading = false;
      });
      _scrollToBottom(animated: false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _connectWebSocket() async {
    final token = await TokenStorage.get();
    _stompClient = StompClient(
      config: StompConfig.sockJS(
        url: '${ApiConstants.baseUrl}/ws',
        onConnect: (frame) {
          if (!mounted) return;
          setState(() => _connected = true);
          _stompClient?.subscribe(
            destination: '/topic/room/${widget.roomId}',
            callback: (frame) {
              if (!mounted || frame.body == null) return;
              try {
                final msg = _parseMessage(frame.body!);
                setState(() => _messages.add(msg));
                _scrollToBottom();
                // Bundle 1.5 (active read gap): 채팅방에 active 상태에서 상대 메시지 수신 시
                // 즉시 markAsRead REST 호출 → 백엔드 AFTER_COMMIT broadcast → sender 화면 "1" 사라짐.
                // 내 메시지는 호출 X (영향 없지만 불필요 트래픽 차단).
                if (msg['senderUserId'] != _myUserId) {
                  _markAsRead();
                }
              } catch (_) {}
            },
          );
          // Bundle 1 G1: read 이벤트 수신 → 내가 보낸 미읽음 메시지 isRead=true (카카오톡식 "1" 사라짐).
          // 상대가 채팅방 진입 시 백엔드 ChatReadEvent → AFTER_COMMIT broadcast.
          _stompClient?.subscribe(
            destination: '/topic/room/${widget.roomId}/read',
            callback: (frame) {
              if (!mounted || frame.body == null) return;
              try {
                final data = jsonDecode(frame.body!) as Map<String, dynamic>;
                final readerUserId = data['readerUserId'] as String?;
                // 내가 읽은 이벤트는 무시 (내 메시지의 1 사라짐 = 상대가 읽었을 때만).
                if (readerUserId == null || readerUserId == _myUserId) return;
                bool changed = false;
                for (int i = 0; i < _messages.length; i++) {
                  final m = _messages[i];
                  if (m['senderUserId'] == _myUserId && m['isRead'] != true) {
                    _messages[i] = {...m, 'isRead': true};
                    changed = true;
                  }
                }
                if (changed) setState(() {});
              } catch (_) {}
            },
          );
        },
        onDisconnect: (_) {
          if (!mounted) return;
          setState(() => _connected = false);
        },
        onWebSocketError: (_) {
          if (!mounted) return;
          setState(() => _connected = false);
        },
        stompConnectHeaders: {
          'Authorization': 'Bearer ${token ?? ''}',
        },
      ),
    );
    _stompClient?.activate();
  }

  Map<String, dynamic> _parseMessage(String body) {
    return jsonDecode(body) as Map<String, dynamic>;
  }

  /// Bundle 1.5: active 상태 새 메시지 도착 시 즉시 read 처리.
  /// 실패해도 화면 흐름 영향 X (silent) — 채팅방 재진입 시 markRead가 보장.
  Future<void> _markAsRead() async {
    try {
      await ApiClient.post('/api/chat/rooms/${widget.roomId}/read', {});
    } catch (_) {}
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty || !_connected) return;

    _stompClient?.send(
      destination: '/app/room/${widget.roomId}',
      body: '{"message":"${text.replaceAll('"', '\\"')}","senderUserId":"${_myUserId ?? ''}"}',
    );
    _inputController.clear();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  @override
  void dispose() {
    _stompClient?.deactivate();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final otherNickname = widget.roomInfo['otherUserNickname'] ?? '';
    final profileUrl = widget.roomInfo['otherUserProfileImageUrl'] as String?;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.surfaceElevated,
              backgroundImage:
                  profileUrl != null ? NetworkImage(profileUrl) : null,
              child: profileUrl == null
                  ? const Icon(Icons.person,
                      color: AppColors.textMuted, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(otherNickname,
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold)),
                // UI polish: STOMP "연결됨" presence처럼 보이는 라벨 제거.
                // 실제 상대방 presence 시스템 없는 상태에서 오해 방지.
                // Bundle 2에서 거래 미니카드로 자연 확장.
                const Text(
                  '거래 채팅',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: Column(
        children: [
          // 거래 상품 배너
          _buildTradeBanner(),
          // 메시지 리스트
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.blue))
                : _messages.isEmpty
                    ? const Center(
                        child: Text('메시지를 보내보세요',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 14)))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        itemCount: _messages.length,
                        itemBuilder: (context, i) {
                          final prev = i > 0 ? _messages[i - 1] : null;
                          return _buildMessageBubble(_messages[i], prev);
                        },
                      ),
          ),
          // 입력창
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildTradeBanner() {
    // Bundle 2-A: 거래 미니카드 — 카드 master 이미지 + 카드명/가격 + 상태 chip + 탭→거래 상세.
    // 사용자 업로드 trade 사진(AuthImage)은 거래 상세에서만, 미니카드는 카드 master 일관성.
    final tradeTitle = (widget.roomInfo['tradeTitle'] as String?) ?? '';
    final cardImageUrl = widget.roomInfo['cardImageUrl'] as String?;
    final tradeStatus = widget.roomInfo['tradeStatus'] as String?;
    final tradePrice = (widget.roomInfo['tradePrice'] as num?)?.toInt();
    final saleListingId = widget.roomInfo['saleListingId'] as String?;

    // 거래/카드 정보 모두 없으면 배너 hide (stale-safe).
    if (tradeTitle.isEmpty && cardImageUrl == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      onTap: saleListingId == null
          ? null
          : () => context.push('/trades/$saleListingId'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: AppColors.surfaceCard,
        child: Row(
          children: [
            CardImage(
              imageUrl: cardImageUrl,
              width: 48,
              height: 67,
              borderRadius: BorderRadius.circular(6),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tradeTitle.isEmpty ? '거래 정보' : tradeTitle,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (tradePrice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatPrice(tradePrice)}원',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (tradeStatus != null) _buildTradeStatusChip(tradeStatus),
          ],
        ),
      ),
    );
  }

  /// Bundle 2-A: 거래 상태 chip. 양 빨강/음 파랑 정책 회피.
  /// OPEN=green / RESERVED=gold / COMPLETED·CANCELED=textMuted gray.
  Widget _buildTradeStatusChip(String status) {
    final (label, color) = switch (status) {
      'OPEN' => ('판매중', AppColors.green),
      'RESERVED' => ('예약중', AppColors.gold),
      'COMPLETED' => ('거래완료', AppColors.textMuted),
      'CANCELED' => ('취소', AppColors.textMuted),
      _ => (status, AppColors.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 콤마 포맷 (반올림 X). Codex 권장: trade.price는 사용자 입력 정수, 원값 그대로 표시.
  String _formatPrice(int price) {
    final str = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buf.write(',');
      buf.write(str[i]);
    }
    return buf.toString();
  }

  Widget _buildMessageBubble(
      Map<String, dynamic> msg, Map<String, dynamic>? prev) {
    // Bundle 2-C: SYSTEM 메시지 — 가운데 회색 텍스트, 말풍선 X.
    // 사기 주의/상태 변경 안내 등. ⚠ 아이콘은 message 내용에 직접 포함 (예: "⚠ 안전한 거래...").
    if (msg['messageType'] == 'SYSTEM') {
      return _buildSystemMessage(msg['message'] as String? ?? '');
    }
    final isMe = msg['senderUserId'] == _myUserId;
    final text = msg['message'] ?? '';
    final time = _formatTime(msg['createdAt']);
    final senderNick = msg['senderNickname'] ?? '';
    final profileUrl = msg['senderProfileImageUrl'] as String?;

    // 같은 sender 연속이면 아바타/이름 생략
    final sameSenderAsPrev = prev != null &&
        prev['senderUserId'] == msg['senderUserId'];

    return Padding(
      padding: EdgeInsets.only(
          bottom: 2, top: sameSenderAsPrev ? 2 : 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isMe
            ? [
                // 읽음 상태 + 시간 row inline (내 메시지 왼쪽, bubble 옆 baseline 정렬).
                // UI polish: 1:1 거래 채팅이라 카카오톡식 "1" 대신 "읽음 / 안읽음" 라벨로 명확화.
                // 안읽음: blue alpha 0.7 / 읽음: textMuted (흐리게)
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg['isRead'] == true ? '읽음' : '안읽음',
                        style: TextStyle(
                          color: msg['isRead'] == true
                              ? AppColors.textMuted
                              : AppColors.blue.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(time,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                // 말풍선 — radius 18→16 / padding horizontal 14→16 (짧은 메시지 캡슐 방지)
                Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.65),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(text,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, height: 1.4)),
                ),
              ]
            : [
                // 상대방 아바타
                if (!sameSenderAsPrev)
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.surfaceElevated,
                    backgroundImage:
                        profileUrl != null ? NetworkImage(profileUrl) : null,
                    child: profileUrl == null
                        ? const Icon(Icons.person,
                            color: AppColors.textMuted, size: 14)
                        : null,
                  )
                else
                  const SizedBox(width: 32),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!sameSenderAsPrev)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4, left: 2),
                        child: Text(senderNick,
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // 상대 말풍선 — radius 18→16 / padding horizontal 14→16 일관성
                        Container(
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.65),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.circular(16),
                              bottomRight: Radius.circular(16),
                            ),
                          ),
                          child: Text(text,
                              style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                  height: 1.4)),
                        ),
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(time,
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 10)),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
      ),
    );
  }

  /// Bundle 2-C: SYSTEM 메시지 — 가운데 회색 작은 텍스트 + 약한 박스.
  /// Codex 권장: 흰 alpha 0.06 배경 + radius 12 + textMuted 11pt + center align.
  Widget _buildSystemMessage(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 10
            : MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputController,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: '메시지 보내기...',
                  hintStyle:
                      TextStyle(color: AppColors.textMuted, fontSize: 14),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _connected ? AppColors.blue : AppColors.textMuted,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(dynamic ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts.toString()).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
