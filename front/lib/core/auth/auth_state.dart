import 'package:flutter/foundation.dart';
import '../storage/token_storage.dart';

/// 로그인/온보딩 상태를 메모리에 보관하는 단일 source of truth.
/// router는 이걸 refreshListenable로 받아서 redirect를 sync로 처리한다.
/// 매 라우팅마다 SecureStorage I/O를 await하는 race를 회피.
class AuthState extends ChangeNotifier {
  AuthState._();
  static final AuthState instance = AuthState._();

  bool _loggedIn = false;
  bool _onboarded = false;
  bool _ready = false;
  bool _suspended = false;
  String? _suspensionReason;

  bool get loggedIn => _loggedIn;
  bool get onboarded => _onboarded;
  bool get ready => _ready;
  bool get suspended => _suspended;
  String? get suspensionReason => _suspensionReason;

  /// 앱 시작 시 1회 호출. SecureStorage에서 한 번 읽어서 메모리에 캐시.
  Future<void> bootstrap() async {
    _loggedIn = await TokenStorage.exists();
    _onboarded = _loggedIn ? await TokenStorage.isOnboarded() : false;
    _ready = true;
    notifyListeners();
  }

  /// 로그인 직후 — 토큰/온보딩 storage write 끝난 뒤 호출.
  void markLoggedIn({required bool onboarded}) {
    _loggedIn = true;
    _onboarded = onboarded;
    notifyListeners();
  }

  /// 온보딩 완료 시.
  void markOnboarded() {
    _onboarded = true;
    notifyListeners();
  }

  void markLoggedOut() {
    _loggedIn = false;
    _onboarded = false;
    _suspended = false;
    _suspensionReason = null;
    notifyListeners();
  }

  /// 정지 감지(403 USER_SUSPENDED 또는 /me suspended=true) → 라우터가 /suspended 게이트로.
  /// reason 은 /me 의 suspensionReason(없을 수 있음). 상태 변할 때만 notify.
  void markSuspended({String? reason}) {
    final changed = !_suspended || (reason != null && reason != _suspensionReason);
    _suspended = true;
    if (reason != null) _suspensionReason = reason;
    if (changed) notifyListeners();
  }

  /// 정지 해제(복구 계정 /me suspended=false) → 게이트 해제.
  void clearSuspended() {
    if (!_suspended) return;
    _suspended = false;
    _suspensionReason = null;
    notifyListeners();
  }
}
