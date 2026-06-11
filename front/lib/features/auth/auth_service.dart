import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../core/auth/auth_state.dart';
import '../../core/network/api_client.dart';
import '../../core/notifications/chat_socket_service.dart';
import '../../core/notifications/push_notification_service.dart';
import '../../core/notifiers/home_session_cache.dart';
import '../../core/storage/token_storage.dart';
import '../../core/widgets/auth_image.dart';
import 'onboarding_draft.dart';

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
    PushNotificationService.registerToken(); // FCM 토큰 등록 (guard로 무해)
    ChatSocketService.connect(); // foreground 채팅 실시간 STOMP
    return requiresOnboarding;
  }

  /// Sign in with Apple. 로그인 후 온보딩 필요 여부 반환. 취소 시 예외.
  static Future<bool> loginWithApple() async {
    final AuthorizationCredentialAppleID credential;
    try {
      credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw Exception('Apple 로그인 취소됨');
      }
      rethrow;
    }
    final identityToken = credential.identityToken;
    if (identityToken == null) throw Exception('Apple 토큰을 받지 못했습니다');

    final response = await ApiClient.post('/api/auth/apple/token', {
      'identityToken': identityToken,
    });
    final data = response['data'] as Map<String, dynamic>;
    final jwt = data['accessToken'] as String;
    final requiresOnboarding = (data['requiresOnboarding'] as bool?) ?? false;
    await TokenStorage.save(jwt);
    await TokenStorage.setOnboarded(!requiresOnboarding);
    AuthState.instance.markLoggedIn(onboarded: !requiresOnboarding);
    PushNotificationService.registerToken(); // FCM 토큰 등록 (guard로 무해)
    ChatSocketService.connect(); // foreground 채팅 실시간 STOMP
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
      ChatSocketService.connect(); // foreground 채팅 실시간 STOMP
      return requiresOnboarding;
    } catch (e) {
      return null;
    }
  }

  static Future<void> logout() async {
    ChatSocketService.disconnect();
    await PushNotificationService.unregister();
    await _googleSignIn.signOut();
    await TokenStorage.delete();
    OnboardingDraft.instance.clear(); // 계정전환/재가입 시 이전 온보딩 입력(특히 14세미만 차단) 잔존 방지
    HomeSessionCache.clear(); // 계정전환 시 이전 유저 자산/포트폴리오 홈 노출 방지
    await clearAuthImageCache(); // 계정전환 시 이전 유저 private 이미지(자산/채팅/프사) 디스크캐시 잔존 방지
    AuthState.instance.markLoggedOut();
  }
}
