import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';

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
    // iOS foreground 표시
    await messaging.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true);

    // 알림 탭으로 앱 열림 (백그라운드/종료 상태)
    (await messaging.getInitialMessage()).let(_handleTap);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    // 토큰 갱신 시 재등록
    messaging.onTokenRefresh.listen((t) {
      _token = t;
      registerToken();
    });
  }

  /// 로그인 후 호출 — 현재 토큰을 백엔드에 등록 (인증 필요).
  static Future<void> registerToken() async {
    if (!_ready) return;
    try {
      _token ??= await FirebaseMessaging.instance.getToken();
      if (_token == null) return;
      await ApiClient.post('/api/notifications/fcm-token', {
        'token': _token,
        'platform': 'ios',
      });
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

  static void _handleTap(RemoteMessage? message) {
    if (message == null) return;
    // TODO(plist 연동 후): message.data['type']/['cardId'] 로 go_router 라우팅.
    debugPrint('[FCM] 알림 탭: ${message.data}');
  }
}

extension _LetNullable<T> on T? {
  void let(void Function(T) fn) {
    final v = this;
    if (v != null) fn(v);
  }
}
