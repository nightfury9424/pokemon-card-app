import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _key = 'access_token';
  static const _onboardedKey = 'onboarded';

  static Future<void> save(String token) async {
    await _storage.write(key: _key, value: token);
  }

  static Future<String?> get() async {
    return await _storage.read(key: _key);
  }

  static Future<void> delete() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _onboardedKey);
  }

  static Future<bool> exists() async {
    final token = await get();
    return token != null && token.isNotEmpty;
  }

  static Future<void> setOnboarded(bool onboarded) async {
    await _storage.write(key: _onboardedKey, value: onboarded ? '1' : '0');
  }

  static Future<bool> isOnboarded() async {
    final v = await _storage.read(key: _onboardedKey);
    return v == '1';
  }
}
