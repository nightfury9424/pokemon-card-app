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
import '../../core/notifications/chat_socket_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/widgets/auth_image.dart';
import '../../core/widgets/card_image.dart';
import '../../core/widgets/user_avatar.dart';
import '../trade/trade_settlement_sheet.dart';

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

class _ChatRoomScreenState extends State<ChatRoomScreen>
    with WidgetsBindingObserver {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  // 키보드 open/close · 새 메시지 시 바닥 재고정 판정용. 사용자가 최신 메시지 근처를
  // 보고 있었을 때만 바닥으로 따라붙는다(과거 대화 스크롤 중엔 강제 점프 금지).
  bool _isNearBottom = true;
  double _lastViewInsetBottom = 0;

  StompClient? _stompClient;
  String? _myUserId;
  bool _loading = true;
  bool _connected = false;
  // 2026-05-28 이미지 메시지 — 업로드 중 + 버튼 spinner + 중복 전송 차단.
  bool _uploadingImage = false;
  // 10MB 제한 (백엔드 MAX_IMAGE_BYTES 동일).
  static const int _kMaxImageBytes = 5 * 1024 * 1024; // B3-12: 5MB 일관(프사·채팅 동일)
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
  // #14: 알림 딥링크 진입 시 roomInfo가 비어 들어옴({}). roomId 기준 GET /rooms/{roomId}로
  // 헤더/거래정보를 hydrate. 정상 진입(목록→extra)이면 이미 채워진 채로 시작 + fetch로 최신화.
  // 가변 state — 기존 코드의 in-place 갱신(optimistic status)도 widget 불변 객체 변형 없이 안전.
  late Map<String, dynamic> _roomInfo = Map<String, dynamic>.from(widget.roomInfo);
  // 헤더 스켈레톤 — sparse 진입(알림)일 때만 의미. hydrate 완료 시 해제.
  bool _roomLoading = true;

  bool get _isSeller {
    final sellerId = (_trade?['seller'] is Map)
        ? (_trade!['seller'] as Map)['userId']?.toString()
        : null;
    return _myUserId != null && sellerId != null && _myUserId == sellerId;
  }

  /// 2026-05-29: BUY chat 에서 BuyOrder 작성자 본인 여부 — chip 클릭으로 상태 변경 가능한 권한 분기.
  /// ChatRoomDto.buyerUserId (BUY chat 에선 BuyOrder.buyerId) == _myUserId.
  bool get _isBuyOrderOwner {
    final contextType = _roomInfo['contextType'] as String?;
    if (contextType != 'BUY') return false;
    final buyerId = _roomInfo['buyerUserId'] as String?;
    return _myUserId != null && buyerId != null && _myUserId == buyerId;
  }

  @override
  void initState() {
    super.initState();
    // 이 방을 보는 동안 전역 inbox 배너 억제 (방 안에선 메시지 bubble 로 보임).
    ChatSocketService.activeRoomId = widget.roomId;
    // 키보드 inset 변화 감지(didChangeMetrics) + 바닥 근접 추적(_onScroll).
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _init();
  }

  /// 스크롤 위치 추적 — 바닥에서 120px 이내면 "최신 근처"로 간주.
  /// 키보드 변화·새 메시지 수신 시 이 플래그가 true 일 때만 자동으로 바닥 고정.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _isNearBottom = (pos.maxScrollExtent - pos.pixels) <= 120;
  }

  /// 키보드 open/close(viewInsets.bottom 변화) 감지 → 직전에 바닥 근처였다면 바닥에 다시 붙인다.
  /// 과거 대화 보는 중(_isNearBottom=false)엔 유지. resizeToAvoidBottomInset 가 body 를
  /// 리사이즈하지만 스크롤 오프셋은 자동 재고정 안 됨.
  /// ★ jumpTo(animated:false) 사용 — didChangeMetrics 는 키보드 애니메이션 동안 매 프레임 fire 되는데,
  ///   여기서 animateTo(200ms)를 매번 던지면 tween 들이 겹치고 네이티브 키보드 애니메이션과 싸워
  ///   '들썩→점프→다시붙음'이 됨. postFrame jumpTo 는 매 프레임 바닥에 즉시 핀 → 한 덩어리로 붙어 따라옴.
  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final inset = View.of(context).viewInsets.bottom; // physical px — 변화 감지용
    if (inset == _lastViewInsetBottom) return;
    _lastViewInsetBottom = inset;
    if (_isNearBottom) _scrollToBottom(animated: false);
  }

  Future<void> _init() async {
    final token = await TokenStorage.get();
    if (token != null) _myUserId = _userIdFromToken(token);
    // #14: roomId 기준 방 상세 hydrate를 먼저 — saleListingId/contextType 등이 채워져야
    // 아래 _refreshTradeStatus(미니카드)와 헤더가 알림 진입에서도 정상 복원됨.
    await _hydrateRoom();
    // Phase 1B: 메시지 history + conversation-state 병렬 fetch. 각자 독립 fail-safe.
    await Future.wait([_loadMessages(), _loadConversationState()]);
    _connectWebSocket();
    // Bundle 2-D hotfix: trade 정보 진입 시 1회 fetch — 미니카드 status/판매자 메뉴 갱신용.
    _refreshTradeStatus();
    // 실거래가 소프트 인터셉터 — 완료된 거래인데 내가 아직 실거래가 미입력이면 시트 먼저.
    _maybePromptSettlement();
  }

  /// 소프트 인터셉터: 완료 거래 + 내가 미입력이면 실거래가 시트 표시('나중에' 가능 → 다음 진입 때 재권유).
  /// SALE chat 만(saleListingId 존재). BUY 호가는 제외.
  Future<void> _maybePromptSettlement() async {
    // B2-12: SALE(saleListingId) + BUY(buyOrderId) 둘 다 — 완료 거래면 실거래가 입력 인터셉터.
    final saleId = _roomInfo['saleListingId'] as String?;
    final buyId = _roomInfo['buyOrderId'] as String?;
    final String statusPath;
    final String submitPath;
    if (saleId != null && saleId.isNotEmpty) {
      statusPath = '/api/trades/$saleId/settlement/me';
      submitPath = '/api/trades/$saleId/settlement';
    } else if (buyId != null && buyId.isNotEmpty) {
      statusPath = '/api/trades/buy-order/$buyId/settlement/me';
      submitPath = '/api/trades/buy-order/$buyId/settlement';
    } else {
      return;
    }
    try {
      final res = await ApiClient.get(statusPath);
      if (!mounted) return;
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null || data['required'] != true) return;
      await TradeSettlementSheet.show(
        context,
        submitPath: submitPath,
        tradeTitle: _roomInfo['tradeTitle'] as String?,
        agreedPrice: (data['agreedPrice'] as num?)?.toInt(),
        prefillPrice: (data['myReportedPrice'] as num?)?.toInt(),
      );
    } catch (_) {
      // silent — 인터셉터 실패는 채팅 흐름에 영향 없음.
    }
  }

  /// #14: roomId 기준 방 상세 fetch → 헤더/거래정보 hydrate.
  /// - 정상 진입: 이미 채워진 _roomInfo를 fetch 결과로 최신화(authoritative).
  /// - 알림 진입: roomInfo가 {} 로 들어오므로 여기서 헤더/거래정보가 채워짐.
  /// 403(비참여자)/404(삭제) → 진입 불가 안내 후 뒤로. 기타 에러는 기존 정보로 진행.
  Future<void> _hydrateRoom() async {
    try {
      final res = await ApiClient.get('/api/chat/rooms/${widget.roomId}');
      if (!mounted) return;
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        setState(() {
          _roomInfo = {..._roomInfo, ...data}; // fetched 우선
          _roomLoading = false;
        });
      } else {
        setState(() => _roomLoading = false);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) {
        AppErrorToast.show(context, '대화방을 열 수 없어요.');
        if (context.canPop()) context.pop();
        return;
      }
      setState(() => _roomLoading = false);
    } catch (_) {
      if (mounted) setState(() => _roomLoading = false);
    }
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
    final saleListingId = _roomInfo['saleListingId'] as String?;
    if (saleListingId == null) return;
    try {
      final res = await ApiClient.get('/api/trades/$saleListingId');
      if (!mounted) return;
      final data = res['data'];
      if (data is Map<String, dynamic>) {
        setState(() => _trade = data);
      }
    } catch (_) {
      // silent — 기존 _roomInfo로 fallback
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
                // 내 메시지는 항상 바닥으로(방금 내가 보냄). 상대 메시지는 바닥 근처일 때만
                // 따라붙고, 과거 대화 보는 중이면 강제 점프 안 함.
                if (msg['senderUserId'] == _myUserId || _isNearBottom) {
                  _scrollToBottom();
                }
                // B3-3: 내 메시지가 나가면 백엔드가 나간 상대를 재초대(clearHiddenForUser) →
                // "상대방이 나갔어요" 배너(conversation-state notice) 재조회로 즉시 사라지게.
                if (msg['senderUserId'] == _myUserId && _blockNotice != null) {
                  _loadConversationState();
                }
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
                  if (_roomInfo['contextType'] == 'BUY') {
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
              subtitle: '여러 장 한 번에 보낼 수 있어요 (최대 5장).',
              onTap: () {
                Navigator.pop(sheetCtx);
                _pickAndUploadMultiImages();
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

  /// B3-9: 앨범에서 여러 장 선택 → 순차 업로드(최대 5장). 카메라는 단일(_pickAndUploadImage).
  /// 각 업로드의 STOMP echo 가 IMAGE 메시지로 도착 → 순서대로 bubble 렌더.
  Future<void> _pickAndUploadMultiImages() async {
    if (_uploadingImage) return;
    try {
      final picker = ImagePicker();
      final List<XFile> picked = await picker.pickMultiImage(
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (picked.isEmpty || !mounted) return;
      const maxBatch = 5;
      final over = picked.length > maxBatch;
      final files = over ? picked.sublist(0, maxBatch) : picked;
      setState(() => _uploadingImage = true);
      int ok = 0;
      int fail = 0;
      for (final x in files) {
        try {
          final length = await File(x.path).length();
          if (length > _kMaxImageBytes) {
            fail++;
            continue;
          }
          await ApiClient.uploadFile(
            '/api/chat/rooms/${widget.roomId}/upload-image',
            x.path,
            field: 'file',
          );
          ok++;
        } catch (_) {
          fail++;
        }
      }
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      if (ok > 0 && fail == 0) {
        AppSuccessToast.show(context,
            over ? '사진 $ok장을 보냈어요 (한 번에 최대 5장)' : '사진 $ok장을 보냈어요');
      } else if (ok > 0) {
        AppErrorToast.show(context, '$ok장 전송, $fail장은 실패했어요');
      } else {
        AppErrorToast.show(context, '이미지 전송에 실패했어요. 다시 시도해주세요.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      AppErrorToast.show(context, '이미지 전송에 실패했어요. 다시 시도해주세요.');
    }
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
    if (ChatSocketService.activeRoomId == widget.roomId) {
      ChatSocketService.activeRoomId = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _stompClient?.deactivate();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // #14: 알림 진입 시 hydrate 전엔 닉네임이 비어있음 → 빈 헤더 대신 로딩/폴백 라벨.
    final rawNickname = (_roomInfo['otherUserNickname'] as String?) ?? '';
    final otherNickname = rawNickname.isNotEmpty
        ? rawNickname
        : (_roomLoading ? '대화 불러오는 중…' : '거래 상대');
    final profileUrl = _roomInfo['otherUserProfileImageUrl'] as String?;

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
            UserAvatar(imageUrl: profileUrl, size: 36), // B2-10: proxy URL → AuthImage
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
          // B3-2: 빈 영역 탭 시 키보드 내림 (translucent → 버튼/입력 등 자식 제스처는 유지).
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: Column(
            children: [
              // Phase 1B: 차단 안내 sticky banner (canSendMessage=false 시 표시).
              if (_blockNotice != null) _buildBlockBanner(_blockNotice!),
              // 거래 상품 배너
              _buildTradeBanner(),
              // 안전/억제 배너 (욕설·사기 경고)
              _buildSafetyBanner(),
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
    final otherUserId = _roomInfo['otherUserId']?.toString();
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
    final otherUserId = _roomInfo['otherUserId']?.toString();
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

  // 신고 시 자동 차단 안내 + 욕설/사기 억제 문구.
  Widget _buildReportNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.gold, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '신고하면 해당 사용자가 자동으로 차단됩니다. 차단은 해제할 수 있지만 접수된 신고는 취소되지 않아요.\n'
              '신중하게 신고해 주세요. 허위·악의적 신고는 이용 제재 대상이 될 수 있습니다.',
              style: TextStyle(
                color: AppColors.gold.withValues(alpha: 0.95),
                fontSize: 12,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
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
                  const SizedBox(height: 10),
                  _buildReportNotice(),
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
                        final detailText = detailController.text.trim();
                        Navigator.pop(ctx);
                        if (!mounted) return;
                        final ok = await AppConfirmDialog.show(
                          context,
                          icon: Icons.report_gmailerrorred_rounded,
                          iconColor: AppColors.red,
                          title: '신고하고 차단할까요?',
                          message: '신고하면 해당 사용자가 자동으로 차단되고, 신고된 채팅 내용은 관리자가 모두 확인합니다.\n'
                              '차단은 나중에 해제할 수 있지만, 접수된 신고는 취소되지 않으니 신중하게 신고해 주세요.\n'
                              '허위·악의적 신고는 이용 제재 대상이 될 수 있습니다.',
                          cancelLabel: '취소',
                          confirmLabel: '신고하고 차단',
                        );
                        if (ok != true || !mounted) return;
                        await _submitReport(selected, detailText);
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
      final res = await ApiClient.post('/api/reports', {
        'targetType': 'CHAT',
        'targetId': widget.roomId,
        'reason': reasonCode,
        'detail': detail,
      });
      if (!mounted) return;
      if (res['status'] != 'success') {
        AppErrorToast.show(
            context,
            (res['message'] is String &&
                    (res['message'] as String).trim().isNotEmpty)
                ? res['message'] as String
                : '신고 접수에 실패했습니다');
        return;
      }
      AppSuccessToast.show(context, '신고가 접수되었습니다');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '신고 접수에 실패했습니다');
    }
  }

  // 안전/억제 배너 — 욕설·사기 경고 + 관리자 적극 협조. 채팅방 상단 상시 노출.
  Widget _buildSafetyBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      color: AppColors.gold.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_rounded, color: AppColors.gold, size: 14),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '포켓폴리오는 직거래 연결 서비스로 거래 당사자가 아닙니다.\n'
              '거래 전 상대방·카드 상태를 직접 확인하세요.\n'
              '욕설·사기·비매너 행위는 자동 차단되며, 수사기관 정보제공 등 가능한 모든 조치로 대응합니다. 외부 송금·개인정보 요구에 주의하세요.',
              style: TextStyle(
                color: AppColors.gold.withValues(alpha: 0.92),
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeBanner() {
    // Bundle 2-A: 거래 미니카드 — 카드 master 이미지 + 카드명/가격 + 상태 chip + 탭→거래 상세.
    // 사용자 업로드 trade 사진(AuthImage)은 거래 상세에서만, 미니카드는 카드 master 일관성.
    // 2026-05-28 BUY chat: contextType ('SALE'/'BUY') 으로 라벨 chip + 상태 매핑 분기.
    final contextType =
        (_roomInfo['contextType'] as String?) ?? 'SALE';
    final isBuy = contextType == 'BUY';

    final tradeTitle = (_roomInfo['tradeTitle'] as String?) ?? '';
    final cardImageUrl = _roomInfo['cardImageUrl'] as String?;
    // Bundle 2-D hotfix: _trade 우선 (최신 status) / 없으면 진입 시점 snapshot.
    // BUY chat 은 _trade fetch X (sale_listing_id null) — roomInfo snapshot 만 신뢰.
    final tradeStatus = isBuy
        ? (_roomInfo['tradeStatus'] as String?)
        : ((_trade?['status'] as String?) ??
            (_roomInfo['tradeStatus'] as String?));
    final tradePrice = isBuy
        ? (_roomInfo['tradePrice'] as num?)?.toInt()
        : ((_trade?['price'] as num?)?.toInt() ??
            (_roomInfo['tradePrice'] as num?)?.toInt());
    final saleListingId = _roomInfo['saleListingId'] as String?;

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

  /// 2026-05-28: BuyOrder 상태 chip — OPEN/RESERVED/COMPLETED/CANCELED 매핑.
  /// B2-12(2026-06-04): SALE 와 통일 — 구매중/거래중/거래완료 3상태 + 취소.
  ///   _buildTradeStatusChip (SALE) pattern mirror. MATCHED 는 legacy(완료로 표기).
  Widget _buildBuyOrderStatusChip(String status) {
    final (label, color) = switch (status) {
      'OPEN' => ('구매중', AppColors.green),
      'RESERVED' => ('거래 중', AppColors.gold),
      'COMPLETED' => ('거래 완료', AppColors.textMuted),
      'MATCHED' => ('거래 완료', AppColors.textMuted), // legacy
      'CANCELED' => ('취소됨', AppColors.textMuted),
      _ => ('상태 확인', AppColors.textMuted),
    };
    // 작성자 본인 + active(OPEN/RESERVED)일 때만 변경 가능 (SALE 대칭).
    final canChange = _isBuyOrderOwner && (status == 'OPEN' || status == 'RESERVED');
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

  /// B2-12(2026-06-04): BuyOrder 상태 변경 sheet — SALE(_showSellerStatusSheet)와 통일.
  /// 구매 중(OPEN) / 거래 중(RESERVED) / 거래 완료(COMPLETED) 3상태 + 구매 호가 취소.
  /// 거래중 모델: RESERVED 변경 시 현재 chat room 이 자동 활성 상대(별도 선택 X).
  Future<void> _showBuyOrderStatusSheet() async {
    final buyOrderId = _roomInfo['buyOrderId'] as String?;
    if (buyOrderId == null || buyOrderId.isEmpty) return;
    final currentStatus = (_roomInfo['tradeStatus'] as String?) ?? 'OPEN';
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
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
            _buyOrderStatusTile(ctx, '구매중', 'OPEN',
                Icons.shopping_cart_rounded, currentStatus, buyOrderId),
            // 거래중 모델: chat_room 에서 거래중 변경 시 현재 chat room 이 자동 활성 상대.
            _buyOrderStatusTile(ctx, '거래 중', 'RESERVED',
                Icons.bookmark_rounded, currentStatus, buyOrderId),
            _buyOrderStatusTile(ctx, '거래 완료', 'COMPLETED',
                Icons.check_circle_rounded, currentStatus, buyOrderId),
            const Divider(color: AppColors.divider, height: 1),
            ListTile(
              leading: const Icon(Icons.cancel_outlined,
                  color: AppColors.red, size: 22),
              title: const Text('구매 호가 삭제',
                  style: TextStyle(
                      color: AppColors.red, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmCancelBuyOrder(buyOrderId);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buyOrderStatusTile(BuildContext ctx, String label, String status,
      IconData icon, String currentStatus, String buyOrderId) {
    final selected = status == currentStatus;
    // B2-4 대칭: OPEN 에서 곧장 거래완료 금지 (거래중 먼저). 백엔드 F409 도 가드.
    final disabled = status == 'COMPLETED' && currentStatus == 'OPEN';
    return ListTile(
      enabled: !disabled,
      leading: Icon(icon,
          color: disabled
              ? AppColors.textMuted
              : selected
                  ? AppColors.blue
                  : AppColors.textSecondary),
      title: Text(label,
          style: TextStyle(
            color: disabled
                ? AppColors.textMuted
                : selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          )),
      subtitle: disabled
          ? const Text('거래중으로 바꾼 뒤 완료할 수 있어요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11))
          : null,
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.blue, size: 20)
          : null,
      onTap: (selected || disabled)
          ? null
          : () {
              Navigator.of(ctx).pop();
              _updateBuyOrderStatus(status, buyOrderId);
            },
    );
  }

  Future<void> _confirmCancelBuyOrder(String buyOrderId) async {
    final confirmed = await AppConfirmDialog.show(
      context,
      title: '구매 호가를 삭제할까요?',
      message: '호가창에서 내 구매 호가가 내려가요.',
      cancelLabel: '취소',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    await _updateBuyOrderStatus('CANCELED', buyOrderId);
  }

  /// B2-12: BuyOrder 상태 변경 API — SALE(_updateTradeStatus)와 통일.
  /// OPEN/RESERVED/COMPLETED: PATCH /api/buy-orders/{id}/status (RESERVED 시 현재 방 = 활성 상대).
  /// CANCELED: DELETE /api/buy-orders/{id}.
  /// 완료 시 실거래가 인터셉터(_maybePromptSettlement) 호출 — SALE 대칭.
  /// 백엔드 broadcastBuyOrderStatusChanged 가 STOMP SYSTEM fan-out — chip 자동 갱신.
  Future<void> _updateBuyOrderStatus(String newStatus, String buyOrderId) async {
    try {
      if (newStatus == 'CANCELED') {
        await ApiClient.delete('/api/buy-orders/$buyOrderId');
      } else {
        // 거래중 모델: RESERVED 변경 시 현재 chat room 을 자동 active 상대로.
        final chatRoomId = newStatus == 'RESERVED' ? widget.roomId : null;
        final res = await ApiClient.patch(
          '/api/buy-orders/$buyOrderId/status',
          data: {
            'data': {
              'status': newStatus,
              if (chatRoomId != null) 'chatRoomId': chatRoomId,
            }
          },
        );
        if (!mounted) return;
        // 백엔드 거부(F409 등)는 HTTP 200 바디(status=fail)로 옴 → 성공 오인 방지.
        if (res['status'] != 'success') {
          final msg = (res['message'] is String &&
                  (res['message'] as String).trim().isNotEmpty)
              ? res['message'] as String
              : '상태를 변경할 수 없어요.';
          AppErrorToast.show(context, msg);
          await _refreshBuyOrderStatus(); // 서버 truth 재동기화
          return;
        }
      }
      if (!mounted) return;
      AppSuccessToast.show(
          context,
          switch (newStatus) {
            'OPEN' => '구매중으로 변경됐어요',
            'RESERVED' => '거래중으로 변경됐어요',
            'COMPLETED' => '거래 완료로 처리됐어요',
            _ => '구매 호가가 취소됐어요',
          });
      // 즉시 chip 갱신 — SYSTEM broadcast 도착 전에도 UI 반영.
      await _refreshBuyOrderStatus(newStatus);
      ChatUnreadNotifier.instance.notifyChanged();
      // 완료 시 실거래가 입력 인터셉터 (SALE 대칭, 수집만).
      if (newStatus == 'COMPLETED' && mounted) {
        await _maybePromptSettlement();
      }
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
        _roomInfo['tradeStatus'] = optimisticStatus;
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
      if (newStatus != null && newStatus != _roomInfo['tradeStatus']) {
        if (!mounted) return;
        setState(() {
          _roomInfo['tradeStatus'] = newStatus;
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
      'RESERVED' => ('거래 중', AppColors.gold),
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
                  UserAvatar(imageUrl: profileUrl, size: 32) // B2-10
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
    final tradeId = _roomInfo['saleListingId'] as String?;
    if (tradeId == null) return;
    final currentStatus = (_trade?['status'] as String?) ??
        (_roomInfo['tradeStatus'] as String?) ?? 'OPEN';
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
            _sellerStatusTile(ctx, '판매중', 'OPEN', Icons.sell_rounded, currentStatus),
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
    // B2-4: 판매중에서 곧장 거래완료 금지(거래중 먼저). 백엔드 F409 도 가드 — BUY 타일과 동일.
    final disabled = status == 'COMPLETED' && currentStatus == 'OPEN';
    return ListTile(
      enabled: !disabled,
      leading: Icon(icon,
          color: disabled
              ? AppColors.textMuted
              : selected
                  ? AppColors.blue
                  : AppColors.textSecondary),
      title: Text(label,
          style: TextStyle(
            color: disabled
                ? AppColors.textMuted
                : selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          )),
      subtitle: disabled
          ? const Text('거래중으로 바꾼 뒤 완료할 수 있어요',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11))
          : null,
      trailing: selected
          ? const Icon(Icons.check_rounded, color: AppColors.blue, size: 20)
          : null,
      onTap: (selected || disabled)
          ? null
          : () {
              Navigator.of(ctx).pop();
              _updateTradeStatus(status);
            },
    );
  }

  Future<void> _updateTradeStatus(String newStatus) async {
    final tradeId = _roomInfo['saleListingId'] as String?;
    if (tradeId == null) return;
    try {
      // 거래중 모델: RESERVED 변경 시 현재 chat room 을 자동 active_chat_room_id 로.
      // chat_room 안에서 거래중 변경 = 이 buyer 와 거래중 의미가 자명. 별도 상대 선택 X.
      final chatRoomId = newStatus == 'RESERVED' ? widget.roomId : null;
      final res = await ApiClient.updateTradeStatus(tradeId, newStatus,
          chatRoomId: chatRoomId);
      if (!mounted) return;
      // 백엔드 거부(F409 등)는 HTTP 200 바디(status=fail)로 옴 → 성공 오인 방지.
      if (res['status'] != 'success') {
        final msg = (res['message'] is String &&
                (res['message'] as String).trim().isNotEmpty)
            ? res['message'] as String
            : '상태를 변경할 수 없어요.';
        AppErrorToast.show(context, msg);
        await _refreshTradeStatus();
        return;
      }
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
      title: '판매글을 삭제할까요?',
      message: '삭제해도 채팅방 대화는 유지돼요.',
      cancelLabel: '취소',
      confirmLabel: '삭제',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      final res = await ApiClient.delete('/api/trades/$tradeId');
      if (!mounted) return;
      if (res['status'] != 'success') {
        AppErrorToast.show(
            context,
            (res['message'] is String &&
                    (res['message'] as String).trim().isNotEmpty)
                ? res['message'] as String
                : '삭제에 실패했어요');
        return;
      }
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
                  UserAvatar(imageUrl: profileUrl, size: 32) // B2-10
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
