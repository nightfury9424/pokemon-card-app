import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../notifiers/chat_unread_notifier.dart';
import '../router/app_router.dart';
import 'chat_socket_service.dart';
import 'in_app_notification.dart';

/// FCM 푸시 알림 — 기기 토큰 등록 + 수신/탭 처리.
/// GoogleService-Info.plist + Push capability 추가 전엔 init()이 guard로 무해(no-op).
/// 백엔드는 in-app Notification 저장 시 FcmService 로 같이 푸시 (NotificationService hook).
class PushNotificationService {
  static bool _ready = false;
  static String? _token;

  /// 앱 시작 시 1회 — Firebase init + 권한 + 핸들러. plist 없으면 조용히 skip.
  static Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[FCM] Firebase 미설정(plist 추가 전) — 푸시 비활성: $e');
      return;
    }
    _ready = true;

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    // 포그라운드: OS 시스템 배너는 끄고(alert:false) 앱 커스텀 인앱 배너로 대체 → 중복 방지.
    // badge/sound 는 유지.
    await messaging.setForegroundNotificationPresentationOptions(
        alert: false, badge: true, sound: true);

    // 포그라운드(앱 켜져 있을 때) 수신 → 상단 커스텀 인앱 배너.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    // 알림 탭으로 앱 열림 (백그라운드/종료 상태)
    (await messaging.getInitialMessage()).let(_handleTap);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    // 토큰 갱신 시 재등록
    messaging.onTokenRefresh.listen((t) {
      _token = t;
      registerToken();
    });
    // 앱 시작 시 즉시 등록 X — 미로그인이면 401. 로그인 흐름/부트스트랩(main)에서 호출.
  }

  /// 로그인 후 호출 — 현재 토큰을 백엔드에 등록 (인증 필요).
  /// iOS: getToken() 전에 APNs 토큰이 Firebase 에 set 되어야 함 → getAPNSToken() 선행 + 재시도.
  static Future<void> registerToken() async {
    if (!_ready) return;
    try {
      if (_token == null) {
        // iOS: APNs 토큰 준비될 때까지 대기 (권한 승인 직후엔 아직 null 가능).
        if (Platform.isIOS) {
          String? apns;
          for (var i = 0; i < 5 && apns == null; i++) {
            apns = await FirebaseMessaging.instance.getAPNSToken();
            if (apns == null) {
              await Future.delayed(const Duration(seconds: 1));
            }
          }
          if (apns == null) {
            debugPrint('[FCM] APNs 토큰 미수신(5회 재시도) — 등록 보류');
            return;
          }
        }
        // FCM 토큰도 null 이면 재시도.
        for (var i = 0; i < 5 && _token == null; i++) {
          _token = await FirebaseMessaging.instance.getToken();
          if (_token == null) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
      if (_token == null) {
        debugPrint('[FCM] FCM 토큰 미수신(재시도 후) — 등록 보류');
        return;
      }
      await ApiClient.post('/api/notifications/fcm-token', {
        'token': _token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      debugPrint('[FCM] 토큰 등록 완료');
    } catch (e) {
      debugPrint('[FCM] 토큰 등록 실패: $e');
    }
  }

  /// 로그아웃 시 호출 — 이 기기 토큰 해제.
  static Future<void> unregister() async {
    if (_token == null) return;
    try {
      await ApiClient.delete('/api/notifications/fcm-token?token=$_token');
    } catch (_) {}
    _token = null;
  }

  /// 포그라운드 수신 — 이미 해당 화면을 보고 있으면 억제, 아니면 인앱 배너 표시.
  static void _onForegroundMessage(RemoteMessage message) {
    final n = message.notification;
    final title = n?.title ?? '';
    final body = n?.body ?? '';
    // 채팅 수신 → 배너 표시 여부와 무관하게 목록/하단탭 unread 즉시 갱신 (foreground 잔존 버그 fix).
    if (message.data['type'] == 'CHAT') {
      ChatUnreadNotifier.instance.notifyChanged();
      // 이미 그 채팅방에 들어와 있으면 배너 억제 — 방 안에선 메시지 bubble 로 보임.
      // URI 문자열 비교(_isCurrentLocation)보다 신뢰성 있는 activeRoomId 단일 신호로
      // STOMP inbox 경로와 통일 (chat_room_screen 의 set/clear 가 진실원).
      final roomId = message.data['roomId']?.toString();
      if (roomId != null && roomId == ChatSocketService.activeRoomId) return;
    }
    if (title.isEmpty && body.isEmpty) return;
    final target = _routePathFor(message.data);
    if (target != null && _isCurrentLocation(target)) return; // 이미 그 채팅방 등(TRADE 등 보조 가드)
    InAppNotification.show(
      title: title,
      body: body,
      imageUrl: message.data['senderImage'] as String?, // 카톡식 상대 프사
      onTap: () => _handleTap(message),
    );
  }

  /// 알림 데이터 → go_router 경로. 지원 안 하는 type 은 null.
  static String? _routePathFor(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'CHAT':
        final roomId = data['roomId'];
        if (roomId != null && '$roomId'.isNotEmpty) return '/chat/$roomId';
        break;
      case 'TRADE': // 관심 거래 상태변경 알림 → 거래 상세 딥링크
        final tradeId = data['tradeId'];
        if (tradeId != null && '$tradeId'.isNotEmpty) return '/trades/$tradeId';
        break;
      case 'BOARD_POST_LIKE': // 게시판 알림 → 게시글 상세(삭제/숨김이면 상세가 404 안내, 크래시·무한로딩 없음)
      case 'BOARD_POST_COMMENT':
      case 'BOARD_COMMENT_REPLY':
        final link = data['linkUrl'];
        if (link != null && '$link'.startsWith('/board/')) return '$link';
        break;
    }
    return null;
  }

  static bool _isCurrentLocation(String path) {
    try {
      final loc = appRouter.routerDelegate.currentConfiguration.uri.toString();
      return loc == path;
    } catch (_) {
      return false;
    }
  }

  /// 알림 탭(백그라운드/종료/배너) → 해당 화면으로 라우팅.
  static void _handleTap(RemoteMessage? message) {
    if (message == null) return;
    final target = _routePathFor(message.data);
    if (target == null) {
      debugPrint('[FCM] 라우팅 대상 없음: ${message.data}');
      return;
    }
    try {
      appRouter.push(target);
    } catch (e) {
      debugPrint('[FCM] 라우팅 실패($target): $e');
    }
  }
}

extension _LetNullable<T> on T? {
  void let(void Function(T) fn) {
    final v = this;
    if (v != null) fn(v);
  }
}
