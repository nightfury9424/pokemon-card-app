import 'dart:convert';

import 'package:stomp_dart_client/stomp_dart_client.dart';

import '../constants/api_constants.dart';
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
          final target = (roomId != null && roomId.isNotEmpty) ? '/chat/$roomId' : null;
          // 이미 그 방을 보고 있으면 배너 억제 (방 안에서는 bubble 로 보임).
          if (target != null && _isCurrentLocation(target)) return;
          InAppNotification.show(
            title: (m['senderName'] ?? '새 메시지').toString(),
            body: (m['preview'] ?? '').toString(),
            imageUrl: m['senderImage']?.toString(),
            onTap: () {
              if (target != null) {
                try {
                  appRouter.push(target);
                } catch (_) {}
              }
            },
          );
        } catch (_) {}
      },
    );
  }

  static bool _isCurrentLocation(String path) {
    try {
      return appRouter.routerDelegate.currentConfiguration.uri.toString() == path;
    } catch (_) {
      return false;
    }
  }

  static void disconnect() {
    try {
      _client?.deactivate();
    } catch (_) {}
    _client = null;
  }
}
