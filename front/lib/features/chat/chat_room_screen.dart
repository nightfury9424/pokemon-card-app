import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';

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
                Text(
                  _connected ? '연결됨' : '연결 중...',
                  style: TextStyle(
                    color: _connected ? AppColors.green : AppColors.textMuted,
                    fontSize: 11,
                  ),
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
    final tradeTitle = widget.roomInfo['tradeTitle'] ?? '';
    final tradeImage = widget.roomInfo['tradeImageUrl'] as String?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surfaceCard,
      child: Row(
        children: [
          if (tradeImage != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(tradeImage,
                  width: 36, height: 36, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          if (tradeImage != null) const SizedBox(width: 10),
          Expanded(
            child: Text(tradeTitle,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
      Map<String, dynamic> msg, Map<String, dynamic>? prev) {
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
                // 시간 (내 메시지 왼쪽)
                Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 2),
                  child: Text(time,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 10)),
                ),
                // 말풍선
                Container(
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.65),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.blue,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
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
                        Container(
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.65),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(18),
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
