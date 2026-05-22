import 'package:flutter/foundation.dart';

/// 채팅 unread 변경 신호 — bottom nav 빨간 점 / 채팅 목록 unread badge 즉시 갱신용.
///
/// 호출 시점:
///   - chat_room 진입 시 (getMessages → 자동 markRead)
///   - chat_room active 상태에서 새 메시지 markAsRead 후
///   - chat_room dispose (혹시 모를 보강)
///
/// listen: main_shell `_BottomNav` — notify 받으면 `_loadUnread()` 호출 → bottom nav badge 즉시 갱신.
class ChatUnreadNotifier extends ChangeNotifier {
  static final instance = ChatUnreadNotifier._();
  ChatUnreadNotifier._();
  void notifyChanged() => notifyListeners();
}
