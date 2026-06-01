import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart' show DioException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/notifiers/chat_unread_notifier.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/widgets/auth_image.dart';
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
  // 2026-05-28 이미지 메시지 — 업로드 중 + 버튼 spinner + 중복 전송 차단.
  bool _uploadingImage = false;
  // 10MB 제한 (백엔드 MAX_IMAGE_BYTES 동일).
  static const int _kMaxImageBytes = 10 * 1024 * 1024;
  // Phase 1B: backend conversation-state — 입력창 비활성화 + 안내 banner.
  // canSendMessage=false 면 send 차단. blockNotice 있으면 sticky banner + placeholder 변경.
  bool _canSendMessage = true;
  String? _blockNotice;
  // Phase 1 hotfix#4: 메뉴 label (차단/차단해제) 분기용. blockedByMe 단일 기준.
  // mutual block 시 한쪽만 해제해도 canSendMessage 는 false 유지 (blockedByOther 가 별도 통제).
  bool _blockedByMe = false;
  // Bundle 2-D hotfix: trade 정보를 chat_room에서 직접 보유 → 미니카드 status 즉시 동기화.
  // SYSTEM 메시지 수신 시 _refreshTradeStatus 호출하여 갱신.
  Map<String, dynamic>? _trade;

  bool get _isSeller {
    final sellerId = (_trade?['seller'] is Map)
        ? (_trade!['seller'] as Map)['userId']?.toString()
        : null;
    return _myUserId != null && sellerId != null && _myUserId == sellerId;
  }

  /// 2026-05-29: BUY chat 에서 BuyOrder 작성자 본인 여부 — chip 클릭으로 상태 변경 가능한 권한 분기.
  /// ChatRoomDto.buyerUserId (BUY chat 에선 BuyOrder.buyerId) == _myUserId.
  bool get _isBuyOrderOwner {
    final contextType = widget.roomInfo['contextType'] as String?;
    if (contextType != 'BUY') return false;
    final buyerId = widget.roomInfo['buyerUserId'] as String?;
    return _myUserId != null && buyerId != null && _myUserId == buyerId;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final token = await TokenStorage.get();
    if (token != null) _myUserId = _userIdFromToken(token);
    // Phase 1B: 메시지 history + conversation-state 병렬 fetch. 각자 독립 fail-safe.
    await Future.wait([_loadMessages(), _loadConversationState()]);
    _connectWebSocket();
    // Bundle 2-D hotfix: trade 정보 진입 시 1회 fetch — 미니카드 status/판매자 메뉴 갱신용.
    _refreshTradeStatus();
  }

  /// Phase 1B: 차단 관계 → 입력창 비활성화 + 안내 banner 상태 fetch.
  /// 실패 시 silent — canSendMessage 기본 true. 전송 시도 시 backend 가드(403)로 fallback.
  Future<void> _loadConversationState() async {
    try {
      final res = await ApiClient.getConversationState(widget.roomId);
      if (!mounted) return;
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return;
      setState(() {
        _canSendMessage = (data['canSendMessage'] as bool?) ?? true;
        _blockNotice = data['blockNotice'] as String?;
        _blockedByMe = (data['blockedByMe'] as bool?) ?? false;
      });
    } catch (_) {
      // silent — fail-open. 전송은 backend 가드가 막음.
    }
  }

  /// trade 정보 fetch — 상단 미니카드 status + _isSeller 판정에 사용.
  /// SYSTEM 메시지(상태 변경/삭제) 수신 시 + 판매자 메뉴 사용 후에도 호출.
  Future<void> _refreshTradeStatus() async {
    final saleListingId = widget.roomInfo['saleListingId'] as String?;
    if (saleListingId == null) return;
    try {
      final res = await ApiClient.get('/api/trades/$saleListingId');
      if (!mounted) return;
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        setState(() => _trade = data);
      }
    } catch (_) {
      // silent — 기존 widget.roomInfo로 fallback
    }
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

  /// Phase 1 hotfix#5: 차단/차단해제 관련 legacy SYSTEM 메시지 hide.
  /// 이전 정책에서 visible SYSTEM 으로 저장된 메시지는 현재 상태와 충돌하므로 렌더링 X.
  /// 현재 차단 상태 안내는 ConversationStateDto 기준 상단 banner 가 단일 진실원.
  static const _legacyBlockStateMessages = <String>{
    '상대방의 설정으로 인해 더 이상 대화할 수 없습니다.',
    '차단한 사용자입니다. 차단을 해제하면 대화할 수 있어요.',
    '차단이 해제되었습니다. 다시 대화할 수 있어요.',
  };

  bool _isLegacyBlockState(Map<String, dynamic> msg) {
    if (msg['messageType'] != 'SYSTEM') return false;
    final body = (msg['message'] as String?) ?? '';
    return _legacyBlockStateMessages.contains(body);
  }

  Future<void> _loadMessages() async {
    try {
      final res = await ApiClient.get('/api/chat/rooms/${widget.roomId}/messages');
      if (!mounted) return;
      final list = (res['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      // hotfix#5: legacy block/unblock SYSTEM 메시지는 channel 에서 제외 (이미 DB 에
      // 저장된 과거 메시지). 신규는 backend 가 더 이상 안 보냄 (silent state event).
      final visible = list.where((m) => !_isLegacyBlockState(m)).toList();
      setState(() {
        _messages.addAll(visible);
        _loading = false;
      });
      _scrollToBottom(animated: false);
      // 채팅방 진입 시 백엔드 getMessages가 자동 markAllAsRead 호출 → bottom nav badge 갱신 신호.
      ChatUnreadNotifier.instance.notifyChanged();
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
                // Phase 1 hotfix#4: STATE_CHANGED 는 silent state event — visible 메시지 아님.
                // backend notifyUnblock 등에서 발행. list 추가 X, conversation-state 재조회만.
                if (msg['messageType'] == 'STATE_CHANGED') {
                  _loadConversationState();
                  ChatUnreadNotifier.instance.notifyChanged();
                  return;
                }
                // hotfix#5: legacy block/unblock SYSTEM 메시지가 혹시 STOMP 로 와도 hide.
                // 신규는 backend 가 안 보내지만 안전 차원 동일 filter.
                if (_isLegacyBlockState(msg)) {
                  _loadConversationState();
                  return;
                }
                // 2026-05-28 Codex 사후 리뷰: STOMP 중복 수신(네트워크 재전송) 시 같은 chatMessageId
                // 가 두 번 append 되어 IMAGE bubble Hero tag 충돌 발생. id 기반 de-dupe.
                final mid = msg['chatMessageId'];
                if (mid != null && _messages.any((m) => m['chatMessageId'] == mid)) {
                  return;
                }
                setState(() => _messages.add(msg));
                _scrollToBottom();
                // Bundle 1.5 (active read gap): 채팅방에 active 상태에서 상대 메시지 수신 시
                // 즉시 markAsRead REST 호출 → 백엔드 AFTER_COMMIT broadcast → sender 화면 "1" 사라짐.
                // 내 메시지는 호출 X (영향 없지만 불필요 트래픽 차단).
                if (msg['senderUserId'] != _myUserId) {
                  _markAsRead();
                }
                // Bundle 2-D hotfix: SYSTEM 메시지 수신 시 trade status 갱신 → 미니카드 즉시 동기화.
                // ChatUnreadNotifier 추가 — buyer가 방 열어둔 동안 chat_screen list도 sync.
                // Phase 1B: SYSTEM 메시지 중 차단 안내가 올 수 있으므로 conversation-state 재조회 →
                // 입력창 즉시 비활성화. 키워드 매칭 대신 항상 재조회 (빈도 낮음).
                if (msg['messageType'] == 'SYSTEM') {
                  // SALE chat 은 _refreshTradeStatus (saleListingId null 가드로 silent skip).
                  // BUY chat 은 _refreshBuyOrderStatus — chip status 갱신 (Codex E).
                  _refreshTradeStatus();
                  if (widget.roomInfo['contextType'] == 'BUY') {
                    _refreshBuyOrderStatus();
                  }
                  _loadConversationState();
                  ChatUnreadNotifier.instance.notifyChanged();
                }
              } catch (_) {}
            },
          );
          // (Bundle 2-D hotfix는 위 메시지 subscribe 콜백 안에서 SYSTEM 메시지일 때 _refreshTradeStatus 호출)
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
      // bottom nav badge 즉시 갱신 (active 상태에서 새 메시지 → read 처리됨).
      ChatUnreadNotifier.instance.notifyChanged();
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

  // ─────────────────────────────────────────────────────────────────
  // 2026-05-28: 채팅 이미지 메시지 (Task 8 MVP)
  // 정책: 1회 1장 / 프론트 압축 (maxWidth 1600, q80) / 10MB / REST upload / AuthImage render.
  // 백엔드: POST /api/chat/rooms/{roomId}/upload-image — multipart field 'file'.
  //   413 IMAGE_TOO_LARGE / 400 UNSUPPORTED_IMAGE_TYPE 등 분기 토스트.
  // ─────────────────────────────────────────────────────────────────

  /// + 버튼 클릭 시 — 카톡/당근식 액션 시트 (앨범/카메라).
  /// useRootNavigator: true (이전 cycle FAB-sheet 가림 fix 동일 패턴).
  Future<void> _showImagePickerSheet() async {
    FocusScope.of(context).unfocus(); // 키보드 내림
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '무엇을 보낼까요?',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            _ImagePickerOption(
              icon: Icons.photo_library_outlined,
              title: '사진 앨범에서 선택',
              subtitle: '카드 앞/뒤, 하자 부위 사진을 보낼 수 있어요.',
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadImage(ImageSource.gallery);
              },
            ),
            _ImagePickerOption(
              icon: Icons.camera_alt_outlined,
              title: '카메라로 촬영',
              subtitle: '실물 인증 사진을 바로 촬영해 보낼 수 있어요.',
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// image_picker로 압축 + 10MB 검증 + multipart upload + 실패 분기 토스트.
  Future<void> _pickAndUploadImage(ImageSource source) async {
    if (_uploadingImage) return;
    try {
      final picker = ImagePicker();
      // maxWidth: 1600 + imageQuality: 80 — image_picker 가 디코드/리사이즈/재인코드 자동.
      // iOS HEIC 입력은 일반적으로 JPEG 출력으로 변환되나 100% 보장 X (사용자 catch).
      // 백엔드 UNSUPPORTED_IMAGE_TYPE 응답 시 사용자에게 명확 안내로 fallback.
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;

      final file = File(picked.path);
      final length = await file.length();
      if (length > _kMaxImageBytes) {
        if (!mounted) return;
        AppErrorToast.show(context, '이미지 용량이 너무 커요. 다른 사진을 선택해주세요.');
        return;
      }

      setState(() => _uploadingImage = true);
      try {
        await ApiClient.uploadFile(
          '/api/chat/rooms/${widget.roomId}/upload-image',
          picked.path,
          field: 'file',
        );
        // STOMP echo 가 자동 도착 → _messages list에 IMAGE 메시지 추가 + bubble 렌더.
        // 별도 list 갱신 불필요.
        if (mounted) AppSuccessToast.show(context, '사진을 보냈어요');
      } on DioException catch (e) {
        if (!mounted) return;
        final status = e.response?.statusCode;
        final reason = e.response?.statusMessage ?? '';
        final body = e.response?.data;
        // 백엔드 reason 추출 (Spring ResponseStatusException 의 reason).
        final reasonText = (body is Map && body['message'] is String)
            ? body['message'] as String
            : reason;
        if (status == 413 || reasonText.contains('IMAGE_TOO_LARGE')) {
          AppErrorToast.show(context, '이미지 용량이 너무 커요. 다른 사진을 선택해주세요.');
        } else if (reasonText.contains('UNSUPPORTED_IMAGE_TYPE') ||
            reasonText.contains('FILE_READ_ERROR') ||
            reasonText.contains('FILE_TOO_SMALL')) {
          AppErrorToast.show(context, '지원하지 않는 이미지 형식입니다. 다른 사진을 선택해주세요.');
        } else if (status == 403) {
          AppErrorToast.show(context, '이 채팅방에 사진을 보낼 권한이 없어요.');
        } else {
          AppErrorToast.show(context, '이미지 전송에 실패했어요. 다시 시도해주세요.');
        }
      } catch (_) {
        if (mounted) AppErrorToast.show(context, '이미지 전송에 실패했어요. 다시 시도해주세요.');
      } finally {
        if (mounted) setState(() => _uploadingImage = false);
      }
    } catch (_) {
      // image_picker 자체 오류 (권한 거부 / 카메라 미사용 가능 등)
      if (!mounted) return;
      AppErrorToast.show(context, source == ImageSource.camera
          ? '카메라를 열 수 없어요. 권한을 확인해주세요.'
          : '사진을 가져올 수 없어요. 권한을 확인해주세요.');
    }
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    otherNickname,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // UI polish: STOMP "연결됨" presence처럼 보이는 라벨 제거.
                  // 실제 상대방 presence 시스템 없는 상태에서 오해 방지.
                  // Bundle 2에서 거래 미니카드로 자연 확장.
                  const Text(
                    '거래 채팅',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '메뉴',
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            onPressed: _showRoomMenu,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      // Phase 1 hotfix#10: 첫 frame opaque 보강. Scaffold bg 외에 body 자체에도
      // SizedBox.expand + Container(AppColors.bg) 명시. NoTransitionPage 와 함께
      // 진입 즉시 화면 전체 덮음 → 이전 trade_detail 잔상 (좌측 관심 버튼 등) 차단.
      body: SizedBox.expand(
        child: Container(
          color: AppColors.bg,
          child: Column(
            children: [
              // Phase 1B: 차단 안내 sticky banner (canSendMessage=false 시 표시).
              if (_blockNotice != null) _buildBlockBanner(_blockNotice!),
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
        ),
      ),
    );
  }

  void _showRoomMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.flag_outlined, color: AppColors.textSecondary),
              title: const Text('신고', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.pop(ctx);
                _showReportSheet();
              },
            ),
            ListTile(
              leading: Icon(
                _blockedByMe ? Icons.person_add_rounded : Icons.person_off_rounded,
                color: _blockedByMe ? AppColors.blue : AppColors.red,
              ),
              title: Text(
                _blockedByMe ? '차단 해제' : '차단',
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (_blockedByMe) {
                  _unblockOtherUser();
                } else {
                  _blockOtherUser();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app_rounded, color: AppColors.textSecondary),
              title: const Text('나가기', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () async {
                Navigator.pop(ctx);
                await _leaveRoom();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Phase 1 hotfix#4: 차단 해제 — 점점점 메뉴 "차단 해제" 트리거.
  /// confirm dialog 후 unblock API → backend notifyUnblock STATE_CHANGED broadcast →
  /// 양쪽 _loadConversationState() 자동 재조회. 본인 화면도 즉시 await refresh.
  /// mutual block 시 상대가 아직 차단 중이면 canSendMessage=false 유지 (banner 그대로).
  Future<void> _unblockOtherUser() async {
    final otherUserId = widget.roomInfo['otherUserId']?.toString();
    if (otherUserId == null || otherUserId.isEmpty) {
      AppErrorToast.show(context, '사용자를 찾을 수 없습니다');
      return;
    }
    final confirm = await AppConfirmDialog.show(
      context,
      title: '차단 해제',
      message: '차단을 해제할까요? 상대도 나를 차단했다면 대화는 계속 제한될 수 있어요.',
      confirmLabel: '차단 해제',
    );
    if (confirm != true) return;
    try {
      await ApiClient.unblockUser(otherUserId);
      if (!mounted) return;
      await _loadConversationState();
      ChatUnreadNotifier.instance.notifyChanged();
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '차단 해제에 실패했습니다');
    }
  }

  Future<void> _blockOtherUser() async {
    final otherUserId = widget.roomInfo['otherUserId']?.toString();
    if (otherUserId == null || otherUserId.isEmpty) {
      AppErrorToast.show(context, '차단할 사용자를 찾을 수 없습니다');
      return;
    }
    final confirm = await AppConfirmDialog.show(
      context,
      title: '사용자 차단',
      message: '차단하면 더 이상 대화할 수 없어요. (채팅방은 그대로 남아 있어요)',
      confirmLabel: '차단',
      destructive: true,
    );
    if (confirm != true) return;
    try {
      await ApiClient.blockUser(otherUserId);
      if (!mounted) return;
      // Phase 1 hotfix: 차단은 hidden_at 자동 set 하지 않음 (정책 분리).
      // 채팅방 유지 + 입력만 비활성화. pop 금지 — 현재 방에 그대로 + banner 갱신.
      await _loadConversationState();
      if (!mounted) return;
      // hotfix#5: 흰색 기본 SnackBar 제거 — 앱 다크 톤 AppInfoToast 로 통일.
      AppInfoToast.show(context, '차단되었습니다');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '차단에 실패했습니다');
    }
  }

  /// Phase 1B: 채팅방 나가기 — confirm 후 backend leaveRoom 호출.
  /// 본인 hidden_at set + chat list refresh 신호 + pop.
  Future<void> _leaveRoom() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: '채팅방 나가기',
      message: '나가면 채팅방 목록에서 사라집니다.',
      confirmLabel: '나가기',
      destructive: true,
    );
    if (confirm != true) return;
    try {
      await ApiClient.leaveRoom(widget.roomId);
      if (!mounted) return;
      ChatUnreadNotifier.instance.notifyChanged();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '나가기에 실패했습니다');
    }
  }

  void _showReportSheet() {
    const reasons = [
      ('FRAUD', '사기 의심'),
      ('FAKE', '가품 의심'),
      ('INSULT', '욕설/비방'),
      ('SPAM', '스팸'),
      ('OTHER', '기타'),
    ];
    String selected = reasons.first.$1;
    final detailController = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '신고 사유 선택',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...reasons.map((reason) => RadioListTile<String>(
                        value: reason.$1,
                        groupValue: selected,
                        onChanged: (value) {
                          if (value != null) setSheetState(() => selected = value);
                        },
                        title: Text(
                          reason.$2,
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                        activeColor: AppColors.blue,
                        contentPadding: EdgeInsets.zero,
                      )),
                  const SizedBox(height: 8),
                  TextField(
                    controller: detailController,
                    minLines: 3,
                    maxLines: 5,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(
                      hintText: '상세 내용을 입력해주세요',
                      hintStyle: TextStyle(color: AppColors.textMuted),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _submitReport(selected, detailController.text.trim());
                      },
                      child: const Text('신고 접수'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(detailController.dispose);
  }

  Future<void> _submitReport(String reasonCode, String detail) async {
    try {
      await ApiClient.post('/api/reports', {
        'targetType': 'CHAT',
        'targetId': widget.roomId,
        'reason': reasonCode,
        'detail': detail,
      });
      if (mounted) AppSuccessToast.show(context, '신고가 접수되었습니다');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '신고 접수에 실패했습니다');
    }
  }

  Widget _buildTradeBanner() {
    // Bundle 2-A: 거래 미니카드 — 카드 master 이미지 + 카드명/가격 + 상태 chip + 탭→거래 상세.
    // 사용자 업로드 trade 사진(AuthImage)은 거래 상세에서만, 미니카드는 카드 master 일관성.
    // 2026-05-28 BUY chat: contextType ('SALE'/'BUY') 으로 라벨 chip + 상태 매핑 분기.
    final contextType =
        (widget.roomInfo['contextType'] as String?) ?? 'SALE';
    final isBuy = contextType == 'BUY';

    final tradeTitle = (widget.roomInfo['tradeTitle'] as String?) ?? '';
    final cardImageUrl = widget.roomInfo['cardImageUrl'] as String?;
    // Bundle 2-D hotfix: _trade 우선 (최신 status) / 없으면 진입 시점 snapshot.
    // BUY chat 은 _trade fetch X (sale_listing_id null) — roomInfo snapshot 만 신뢰.
    final tradeStatus = isBuy
        ? (widget.roomInfo['tradeStatus'] as String?)
        : ((_trade?['status'] as String?) ??
            (widget.roomInfo['tradeStatus'] as String?));
    final tradePrice = isBuy
        ? (widget.roomInfo['tradePrice'] as num?)?.toInt()
        : ((_trade?['price'] as num?)?.toInt() ??
            (widget.roomInfo['tradePrice'] as num?)?.toInt());
    final saleListingId = widget.roomInfo['saleListingId'] as String?;

    // 거래/카드 정보 모두 없으면 배너 hide (stale-safe).
    if (tradeTitle.isEmpty && cardImageUrl == null) {
      return const SizedBox.shrink();
    }

    return InkWell(
      // SALE: 거래글 상세 진입. BUY: 현재는 BuyOrder 상세 화면 없음 → 비활성 (Codex K, 다음 cycle).
      onTap: (isBuy || saleListingId == null)
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
                  // 라벨 chip [판매]/[구매] — 호가 색 정책 (ASK=파랑, BID=빨강).
                  // 글 타입 기준 (사용자 명시) — "내 입장" 아님.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildContextLabelChip(isBuy: isBuy),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          tradeTitle.isEmpty ? '거래 정보' : tradeTitle,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (tradePrice != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      // BUY 면 "희망가", SALE 면 "판매가" — 문맥 명확화.
                      isBuy
                          ? '희망가 ${_formatPrice(tradePrice)}원'
                          : '${_formatPrice(tradePrice)}원',
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
            if (tradeStatus != null)
              isBuy
                  ? _buildBuyOrderStatusChip(tradeStatus)
                  : _buildTradeStatusChip(tradeStatus),
          ],
        ),
      ),
    );
  }

  /// 2026-05-28: 채팅방 라벨 chip — 글 타입 기준 [판매]/[구매].
  /// 호가 색 정책 (feedback_color_policy + feedback_hoga_design_invariants):
  ///  - ASK(판매) = 파랑 / BID(구매) = 빨강. 옅은 톤으로 chip background.
  Widget _buildContextLabelChip({required bool isBuy}) {
    final color = isBuy ? AppColors.red : AppColors.blue;
    final label = isBuy ? '구매' : '판매';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// 2026-05-28: BuyOrder 상태 chip — OPEN/MATCHED/CANCELED 매핑.
  /// 2026-05-29: BuyOrder 작성자 본인 + OPEN 일 때만 chevron + 클릭 → 상태 변경 sheet.
  ///   _buildTradeStatusChip (SALE) pattern mirror. BuyOrder 도메인은 종결 비가역 (Codex G).
  Widget _buildBuyOrderStatusChip(String status) {
    final (label, color) = switch (status) {
      'OPEN' => ('구매중', AppColors.green),
      'MATCHED' => ('매칭 완료', AppColors.textMuted),
      'CANCELED' => ('취소됨', AppColors.textMuted),
      _ => ('상태 확인', AppColors.textMuted),
    };
    // BuyOrder 작성자 본인 + OPEN 일 때만 변경 가능 (MATCHED/CANCELED 종결 비가역).
    final canChange = _isBuyOrderOwner && status == 'OPEN';
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: canChange
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: color,
                ),
              ],
            )
          : Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    if (canChange) {
      return GestureDetector(
        onTap: _showBuyOrderStatusSheet,
        behavior: HitTestBehavior.opaque,
        child: chip,
      );
    }
    return chip;
  }

  /// 2026-05-29: BuyOrder 상태 변경 sheet — 작성자 본인이 OPEN 일 때만 호출.
  /// 옵션 2개: 취소(CANCELED) / 매칭 완료(MATCHED). 둘 다 비가역 — confirm dialog 필수 (Codex G).
  Future<void> _showBuyOrderStatusSheet() async {
    final buyOrderId = widget.roomInfo['buyOrderId'] as String?;
    if (buyOrderId == null || buyOrderId.isEmpty) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '구매 호가 상태 변경',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '한 번 변경하면 되돌릴 수 없어요.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline,
                  color: AppColors.green),
              title: const Text('매칭 완료',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              subtitle: const Text('이 채팅 상대와 거래가 성사됐어요.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              onTap: () => Navigator.pop(sheetCtx, 'MATCHED'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.cancel_outlined, color: AppColors.red),
              title: const Text('구매 호가 취소',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              subtitle: const Text('호가창에서 내 구매 호가를 내릴게요.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              onTap: () => Navigator.pop(sheetCtx, 'CANCELED'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    // 비가역 confirm — AppConfirmDialog 패턴 일관.
    final label = action == 'MATCHED' ? '매칭 완료' : '구매 호가 취소';
    final confirmed = await AppConfirmDialog.show(
      context,
      title: '$label 처리할까요?',
      message: '한 번 처리하면 되돌릴 수 없어요.',
      confirmLabel: '$label 처리',
      destructive: action == 'CANCELED',
    );
    if (confirmed != true || !mounted) return;
    await _updateBuyOrderStatus(action, buyOrderId);
  }

  /// 2026-05-29: BuyOrder 상태 변경 API 호출 + 토스트.
  /// MATCHED: POST /api/buy-orders/{id}/match (tradeId optional, MVP는 body 빈 객체).
  /// CANCELED: DELETE /api/buy-orders/{id}.
  /// 백엔드 broadcastBuyOrderStatusChanged 가 STOMP SYSTEM fan-out — chip 자동 갱신 (Codex E).
  Future<void> _updateBuyOrderStatus(String newStatus, String buyOrderId) async {
    try {
      if (newStatus == 'MATCHED') {
        await ApiClient.post('/api/buy-orders/$buyOrderId/match', {});
      } else if (newStatus == 'CANCELED') {
        await ApiClient.delete('/api/buy-orders/$buyOrderId');
      }
      if (!mounted) return;
      AppSuccessToast.show(
          context,
          newStatus == 'MATCHED'
              ? '매칭 완료로 처리됐어요'
              : '구매 호가가 취소됐어요');
      // 즉시 chip 갱신 — SYSTEM broadcast 도착 전에도 UI 반영.
      await _refreshBuyOrderStatus(newStatus);
    } catch (e) {
      if (!mounted) return;
      AppErrorToast.show(context, '상태 변경에 실패했어요. 다시 시도해주세요.');
    }
  }

  /// 2026-05-29: BUY chat 의 chip status 갱신.
  /// _refreshTradeStatus 의 BuyOrder 버전 — saleListingId null 가드로 SALE 패턴이
  /// silent return 하므로 BUY 는 별도 메서드. SYSTEM 수신 시 + 본인 변경 직후 호출.
  Future<void> _refreshBuyOrderStatus([String? optimisticStatus]) async {
    if (!mounted) return;
    // optimistic = 본인 변경 직후 STOMP echo 대기 X. roomInfo 직접 patch + setState.
    if (optimisticStatus != null) {
      setState(() {
        widget.roomInfo['tradeStatus'] = optimisticStatus;
      });
      return;
    }
    // STOMP SYSTEM 수신 시 — 백엔드 fetch 로 truth 동기화. /api/chat/rooms 에서 내 방 찾아 merge.
    try {
      final res = await ApiClient.get('/api/chat/rooms');
      final list = (res['data'] as List?) ?? const [];
      final me = list
          .whereType<Map>()
          .firstWhere(
              (r) => r['chatRoomId'] == widget.roomId,
              orElse: () => const {})
          .cast<String, dynamic>();
      final newStatus = me['tradeStatus'] as String?;
      if (newStatus != null && newStatus != widget.roomInfo['tradeStatus']) {
        if (!mounted) return;
        setState(() {
          widget.roomInfo['tradeStatus'] = newStatus;
        });
      }
    } catch (_) {
      // silent — chip 갱신 실패는 critical 아님.
    }
  }

  /// Bundle 2-A: 거래 상태 chip. 양 빨강/음 파랑 정책 회피.
  /// 판매글 상태 4종: OPEN=green / RESERVED=gold / COMPLETED·DELETED=textMuted gray.
  /// CANCELED는 판매글 상태에 부적합 (주문/결제 상태가 아님) → 제거 (2026-05-22).
  Widget _buildTradeStatusChip(String status) {
    final (label, color) = switch (status) {
      'OPEN' => ('판매중', AppColors.green),
      'RESERVED' => ('예약 중', AppColors.gold),
      'COMPLETED' => ('거래 완료', AppColors.textMuted),
      'DELETED' => ('삭제됨', AppColors.textMuted),
      // fallback: '판매중' X — unknown status를 OPEN처럼 표시하면 거래 위험.
      _ => ('상태 확인', AppColors.textMuted),
    };
    // 판매자 + active(OPEN/RESERVED)일 때만 chip 클릭으로 상태 변경 sheet.
    final canChange = _isSeller && (status == 'OPEN' || status == 'RESERVED');
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: canChange
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 2),
                // 판매자 + active일 때만 화살표 — 클릭 가능 affordance.
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 14,
                  color: color,
                ),
              ],
            )
          : Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
    if (canChange) {
      return GestureDetector(
        onTap: _showSellerStatusSheet,
        behavior: HitTestBehavior.opaque,
        child: chip,
      );
    }
    return chip;
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
    // 2026-05-28: 이미지 메시지 — AuthImage (JWT) 로 proxy URL fetch + 탭 → 전체화면.
    if (msg['messageType'] == 'IMAGE') {
      return _buildImageBubble(msg, prev);
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

  /// Bundle 2-D hotfix: 판매자 시점만 — 채팅방에서 바로 상태 변경/삭제.
  /// 거래 완료는 finalPrice 필요해서 별도 (Bundle 2-B+).
  void _showSellerStatusSheet() {
    final tradeId = widget.roomInfo['saleListingId'] as String?;
    if (tradeId == null) return;
    final currentStatus = (_trade?['status'] as String?) ??
        (widget.roomInfo['tradeStatus'] as String?) ?? 'OPEN';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            _sellerStatusTile(ctx, '판매 중', 'OPEN', Icons.sell_rounded, currentStatus),
            // 거래중 모델: chat_room 에서 거래중 변경 시 현재 chat room 이 자동으로 활성 상대.
            // 별도 partner select sheet 없이 widget.roomId 가 active_chat_room_id 가 됨.
            _sellerStatusTile(ctx, '거래 중', 'RESERVED', Icons.bookmark_rounded, currentStatus),
            _sellerStatusTile(ctx, '거래 완료', 'COMPLETED', Icons.check_circle_rounded, currentStatus),
            const Divider(color: AppColors.divider, height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.red, size: 22),
              title: const Text('판매글 삭제',
                  style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteTrade(tradeId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sellerStatusTile(BuildContext ctx, String label, String status,
      IconData icon, String currentStatus) {
    final selected = status == currentStatus;
    return ListTile(
      leading: Icon(icon,
          color: selected ? AppColors.blue : AppColors.textSecondary),
      title: Text(label,
          style: TextStyle(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          )),
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.blue, size: 20)
          : null,
      onTap: selected
          ? null
          : () {
              Navigator.of(ctx).pop();
              _updateTradeStatus(status);
            },
    );
  }

  Future<void> _updateTradeStatus(String newStatus) async {
    final tradeId = widget.roomInfo['saleListingId'] as String?;
    if (tradeId == null) return;
    try {
      // 거래중 모델: RESERVED 변경 시 현재 chat room 을 자동 active_chat_room_id 로.
      // chat_room 안에서 거래중 변경 = 이 buyer 와 거래중 의미가 자명. 별도 상대 선택 X.
      final chatRoomId = newStatus == 'RESERVED' ? widget.roomId : null;
      await ApiClient.updateTradeStatus(tradeId, newStatus, chatRoomId: chatRoomId);
      if (!mounted) return;
      AppSuccessToast.show(context, '상태가 변경되었습니다');
      await _refreshTradeStatus();
      await _loadConversationState();
      // Bundle 2-D hotfix: 채팅 목록 list refresh 신호.
      ChatUnreadNotifier.instance.notifyChanged();
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '상태 변경에 실패했어요');
    }
  }

  Future<void> _confirmDeleteTrade(String tradeId) async {
    final ok = await AppConfirmDialog.show(
      context,
      title: '판매글 삭제',
      message: '삭제해도 채팅방 대화는 유지돼요.\n진행하시겠어요?',
      cancelLabel: '취소',
      confirmLabel: '삭제',
    );
    if (ok != true || !mounted) return;
    try {
      await ApiClient.delete('/api/trades/$tradeId');
      if (!mounted) return;
      AppSuccessToast.show(context, '판매글이 삭제되었어요');
      await _refreshTradeStatus();
      ChatUnreadNotifier.instance.notifyChanged();
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '삭제에 실패했어요');
    }
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
          // 2026-05-28 이미지 메시지 — 좌측 + 버튼. canSend && _connected && !uploading.
          GestureDetector(
            onTap: (_canSendMessage && _connected && !_uploadingImage)
                ? _showImagePickerSheet
                : null,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (_canSendMessage && _connected && !_uploadingImage)
                    ? AppColors.surfaceElevated
                    : AppColors.divider,
                shape: BoxShape.circle,
              ),
              child: _uploadingImage
                  ? const Padding(
                      padding: EdgeInsets.all(9),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : const Icon(Icons.add_rounded,
                      color: AppColors.textSecondary, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                // Phase 1B: 차단 관계 시 입력창 색상 비활성 톤.
                color: _canSendMessage
                    ? AppColors.surfaceElevated
                    : AppColors.divider,
                borderRadius: BorderRadius.circular(22),
              ),
              child: TextField(
                controller: _inputController,
                enabled: _canSendMessage,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: _canSendMessage
                      ? '메시지 보내기...'
                      : '대화할 수 없습니다',
                  hintStyle: const TextStyle(
                      color: AppColors.textMuted, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            // Phase 1B: canSendMessage && _connected 둘 다 true일 때만 활성.
            onTap: (_canSendMessage && _connected) ? _sendMessage : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (_canSendMessage && _connected)
                    ? AppColors.blue
                    : AppColors.textMuted,
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

  /// Phase 1B: 차단 안내 sticky banner — AppBar 아래, 거래 미니카드 위.
  /// 문구는 짧게 (입력 placeholder가 보조).
  Widget _buildBlockBanner(String notice) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF332B1A),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFFDE68A), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              notice,
              style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 12),
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

  /// 2026-05-28: IMAGE 메시지 버블 — AuthImage(JWT) 로 proxy URL fetch.
  /// 가로 화면 60% / Hero 애니메이션 + 탭 시 InteractiveViewer 전체화면.
  /// SALE chat 의 텍스트 bubble 양쪽 layout (읽음/시간) 동일 패턴.
  Widget _buildImageBubble(Map<String, dynamic> msg, Map<String, dynamic>? prev) {
    final isMe = msg['senderUserId'] == _myUserId;
    final url = msg['message'] as String? ?? '';
    final time = _formatTime(msg['createdAt']);
    final senderNick = msg['senderNickname'] ?? '';
    final profileUrl = msg['senderProfileImageUrl'] as String?;
    final sameSenderAsPrev =
        prev != null && prev['senderUserId'] == msg['senderUserId'];

    final width = MediaQuery.of(context).size.width * 0.6;
    final heroTag = 'chat-image-${msg['chatMessageId']}';

    final imageBubble = GestureDetector(
      onTap: () => _openFullscreenImage(url, heroTag),
      child: Hero(
        tag: heroTag,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AuthImage(
            url: url,
            width: width,
            height: width,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: 2, top: sameSenderAsPrev ? 4 : 10),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: isMe
            ? [
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
                imageBubble,
              ]
            : [
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
                        imageBubble,
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

  /// 2026-05-28: 이미지 전체화면 viewer — PageRouteBuilder + Hero + InteractiveViewer.
  /// HolographicCardViewer 재사용 X — 카드 전용 tilt/holographic 효과가 사진에 부적합 (Codex J).
  void _openFullscreenImage(String url, String heroTag) {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => _FullscreenImageViewer(
          url: url,
          heroTag: heroTag,
        ),
      ),
    );
  }
}

/// 2026-05-28: 액션 시트 옵션 row (앨범/카메라).
class _ImagePickerOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ImagePickerOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: AppColors.blueLight, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          height: 1.45)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 2026-05-28: 채팅 이미지 전체화면 — Hero + InteractiveViewer + 탭/swipe-down 닫기.
class _FullscreenImageViewer extends StatelessWidget {
  final String url;
  final String heroTag;
  const _FullscreenImageViewer({required this.url, required this.heroTag});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 본체 — pinch/double-tap zoom + 탭 닫기.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  maxScale: 4.0,
                  child: Center(
                    child: Hero(
                      tag: heroTag,
                      child: AuthImage(
                        url: url,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 상단 닫기 X.
            Positioned(
              top: 12,
              right: 12,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
