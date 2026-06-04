import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../auth/auth_state.dart';
import '../constants/api_constants.dart';
import '../network/api_client.dart';
import '../notifiers/chat_unread_notifier.dart';
import '../router/app_router.dart';
import '../storage/token_storage.dart';
import 'in_app_notification.dart';

/// 앱 전역 STOMP 연결 — foreground 채팅 실시간 보강.
///
/// iOS foreground 에서 FCM `onMessage` 가 신뢰성 있게 발화하지 않아(임베딩/델리게이트 이슈)
/// 인앱 배너·목록 갱신이 죽는 문제를 우회한다. 채팅방(chat_room)은 `/topic/room/{id}` 를
/// 방 열려있을 때만 구독하므로, 목록 화면·앱 어디서든 받으려면 전역 user-topic 구독이 필요.
///
/// 흐름: 로그인 후 connect → `/user/queue/inbox` 구독 →
///   새 메시지: ChatUnreadNotifier(목록/하단탭 갱신) + (그 방을 안 보고 있으면) 카톡식 인앱 배너.
/// 백그라운드/종료 알림은 FCM 이 담당(이건 foreground 전용). 로그아웃 시 disconnect.
class ChatSocketService {
  static StompClient? _client;
  static final _LifecycleObserver _lifecycle = _LifecycleObserver();
  static bool _observing = false;

  /// foreground 정지 감지 poll — 관리자가 정지하면 재접 없이 그 즉시(최대 ~20s) 게이트로 잠금.
  /// 정지자의 /api/users/me 는 allowlist 라 200 + suspended:true 로 오므로 body 검사.
  static Timer? _suspendPoll;
  static const Duration _suspendPollInterval = Duration(seconds: 20);

  /// 현재 열려있는 채팅방 id — 그 방의 메시지면 inbox 배너 억제(방 안에선 bubble 로 보임).
  /// chat_room_screen 의 initState 에서 set, dispose 에서 clear.
  static String? activeRoomId;

  static Future<void> connect() async {
    if (_client != null) return;
    final token = await TokenStorage.get();
    if (token == null || token.isEmpty) return;
    if (_client != null) return; // await 사이 재진입 가드
    _client = StompClient(
      config: StompConfig.sockJS(
        url: '${ApiConstants.baseUrl}/ws',
        onConnect: _onConnect,
        onDisconnect: (_) {},
        onWebSocketError: (_) {},
        reconnectDelay: const Duration(seconds: 5),
        stompConnectHeaders: {'Authorization': 'Bearer $token'},
      ),
    );
    _client?.activate();
    if (!_observing) {
      WidgetsBinding.instance.addObserver(_lifecycle);
      _observing = true;
    }
    _startSuspendPoll();
  }

  /// 정지 감지 poll 시작(중복 가드). connect 시 + resume 시 호출.
  static void _startSuspendPoll() {
    _suspendPoll?.cancel();
    _suspendPoll = Timer.periodic(_suspendPollInterval, (_) => _checkSuspended());
  }

  /// /me 의 suspended 플래그 검사 → true 면 즉시 게이트(markSuspended). 이미 정지면 skip.
  static Future<void> _checkSuspended() async {
    if (!AuthState.instance.loggedIn || AuthState.instance.suspended) return;
    try {
      final res = await ApiClient.get('/api/users/me');
      final data = res['data'] as Map<String, dynamic>?;
      if (data != null && data['suspended'] == true) {
        AuthState.instance.markSuspended(
          reason: (data['suspensionReason'] as String?)?.trim(),
        );
      }
    } catch (_) {
      // 네트워크 오류는 무시(다음 tick 재시도). 가변 mutation 은 어차피 403 으로 막힘.
    }
  }

  /// 앱 복귀(resumed) — iOS 가 백그라운드에서 TCP 소켓을 조용히 끊어도 라이브러리가
  /// 한참 감지 못 할 수 있어, 강제로 새 핸드셰이크. + 백그라운드 동안 FCM 으로만 도착한
  /// 메시지가 목록에 반영되도록 unread 갱신.
  static void _onResume() {
    if (_client == null) return; // 로그인/연결된 적 없으면 skip
    try {
      _client?.deactivate();
    } catch (_) {}
    _client = null;
    connect();
    ChatUnreadNotifier.instance.notifyChanged();
    // 백그라운드 동안 정지됐을 수 있으니 복귀 즉시 1회 확인(poll tick 기다리지 않음).
    _checkSuspended();
  }

  static void _onConnect(StompFrame frame) {
    _client?.subscribe(
      destination: '/user/queue/inbox',
      callback: (f) {
        if (f.body == null) return;
        try {
          final m = jsonDecode(f.body!) as Map<String, dynamic>;
          // 목록/하단탭 unread 즉시 갱신 (배너 표시 여부와 무관).
          ChatUnreadNotifier.instance.notifyChanged();
          final roomId = m['roomId']?.toString();
          // 이미 그 방을 보고 있으면 배너 억제 (방 안에서는 bubble 로 보임).
          if (roomId != null && roomId == activeRoomId) return;
          InAppNotification.show(
            title: (m['senderName'] ?? '새 메시지').toString(),
            body: (m['preview'] ?? '').toString(),
            imageUrl: m['senderImage']?.toString(),
            onTap: () {
              if (roomId != null && roomId.isNotEmpty) {
                try {
                  // 상대 이름/프사 전달 → 채팅방 헤더에 표시 (extra 없으면 "거래 채팅" fallback).
                  appRouter.push('/chat/$roomId', extra: {
                    'chatRoomId': roomId,
                    'otherUserNickname': m['senderName'],
                    'otherUserProfileImageUrl': m['senderImage'],
                  });
                } catch (_) {}
              }
            },
          );
        } catch (_) {}
      },
    );
  }

  static void disconnect() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(_lifecycle);
      _observing = false;
    }
    _suspendPoll?.cancel();
    _suspendPoll = null;
    try {
      _client?.deactivate();
    } catch (_) {}
    _client = null;
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ChatSocketService._onResume();
    }
  }
}
