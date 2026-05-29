import 'package:google_sign_in/google_sign_in.dart';
import '../../core/auth/auth_state.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../admin/admin_api.dart';

final _googleSignIn = GoogleSignIn(
  scopes: ['email', 'profile'],
);

class AuthService {
  /// 로그인 후 온보딩이 필요한지 여부를 반환 (true면 /onboarding으로 분기)
  static Future<bool> loginWithGoogle() async {
    final account = await _googleSignIn.signIn();
    if (account == null) throw Exception('구글 로그인 취소됨');

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) throw Exception('ID 토큰을 받지 못했습니다');

    final response = await ApiClient.post('/api/auth/google/token', {
      'idToken': idToken,
    });

    final data = response['data'] as Map<String, dynamic>;
    final jwt = data['accessToken'] as String;
    final requiresOnboarding = (data['requiresOnboarding'] as bool?) ?? false;
    await TokenStorage.save(jwt);
    await TokenStorage.setOnboarded(!requiresOnboarding);
    AuthState.instance.markLoggedIn(onboarded: !requiresOnboarding);
    // 2026-05-29 admin Stage 0 — 로그인 직후 probe (403 silent).
    // unawaited — 로그인 흐름 지연 X. 결과 AuthState.markAdminProbe 로 캐시.
    AdminApi.probeIsAdmin();
    return requiresOnboarding;
  }

  /// dev 로그인. 반환: requiresOnboarding (true/false). 실패 시 null.
  static Future<bool?> devLogin() async {
    try {
      final response = await ApiClient.post('/api/auth/dev/login', {});
      final data = response['data'] as Map<String, dynamic>;
      final jwt = data['accessToken'] as String;
      final requiresOnboarding = (data['requiresOnboarding'] as bool?) ?? false;
      await TokenStorage.save(jwt);
      await TokenStorage.setOnboarded(!requiresOnboarding);
      AuthState.instance.markLoggedIn(onboarded: !requiresOnboarding);
      AdminApi.probeIsAdmin();
      return requiresOnboarding;
    } catch (e) {
      return null;
    }
  }

  static Future<void> logout() async {
    await _googleSignIn.signOut();
    await TokenStorage.delete();
    AuthState.instance.markLoggedOut();
  }
}
