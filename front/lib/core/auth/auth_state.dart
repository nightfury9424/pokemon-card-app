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
  // 2026-05-29 admin Stage 0 — bootstrap/로그인 직후 /api/admin/whoami probe 결과 캐시.
  // 403 = 비-admin (silent). 200 + isAdmin=true 시에만 true. 로그아웃 시 reset.
  bool _isAdmin = false;

  bool get loggedIn => _loggedIn;
  bool get onboarded => _onboarded;
  bool get ready => _ready;
  bool get isAdmin => _isAdmin;

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
    _isAdmin = false;
    notifyListeners();
  }

  /// 2026-05-29: /api/admin/whoami probe 결과 set. 비-admin (403) 도 false 명시.
  void markAdminProbe({required bool isAdmin}) {
    if (_isAdmin != isAdmin) {
      _isAdmin = isAdmin;
      notifyListeners();
    }
  }
}
