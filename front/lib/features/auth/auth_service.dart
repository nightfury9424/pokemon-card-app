import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';

class AuthService {
  static Future<void> loginWithKakao() async {
    OAuthToken token;

    if (await isKakaoTalkInstalled()) {
      token = await UserApi.instance.loginWithKakaoTalk()
          .timeout(const Duration(seconds: 30));
    } else {
      token = await UserApi.instance.loginWithKakaoAccount()
          .timeout(const Duration(seconds: 30));
    }

    final response = await ApiClient.post('/api/auth/kakao/token', {
      'kakaoAccessToken': token.accessToken,
    });

    final jwt = response['data']['accessToken'];
    await TokenStorage.save(jwt);
  }

  static Future<bool> devLogin() async {
    try {
      final response = await ApiClient.post('/api/auth/dev/login', {});
      final jwt = response['data']['accessToken'];
      await TokenStorage.save(jwt);
      return true;
    } catch (e) {
      print('[AuthService] 개발 로그인 실패: $e');
      return false;
    }
  }

  static Future<void> logout() async {
    await UserApi.instance.logout();
    await TokenStorage.delete();
  }
}
