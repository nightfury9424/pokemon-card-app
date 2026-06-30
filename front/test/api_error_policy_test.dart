import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/network/api_client.dart';
import 'package:front/core/network/api_error_policy.dart';

/// silent 의미 재정의 검증 — silent 은 '전역 토스트 표시'만 억제, 인증·계정 lifecycle 은 항상.
void main() {
  group('ApiErrorPolicy.decide', () {
    test('USER_SUSPENDED → 게이트만(토스트·세션정리 없음, suppressToast 무관)', () {
      final a = ApiErrorPolicy.decide(ApiErrorInfo(
          statusCode: 403, code: 'USER_SUSPENDED', message: '정지', suppressToast: true));
      expect(a.markSuspended, isTrue);
      expect(a.showToast, isFalse);
      expect(a.clearAuthSession, isFalse);
    });

    test('★silent + 401 → 세션정리 O · 토스트 X', () {
      final a = ApiErrorPolicy.decide(ApiErrorInfo(
          statusCode: 401, isAuthError: true, message: '만료', suppressToast: true));
      expect(a.clearAuthSession, isTrue); // 자동 로그아웃 항상
      expect(a.showToast, isFalse); // 표시만 억제
      expect(a.markSuspended, isFalse);
    });

    test('non-silent + 401 → 세션정리 O · 토스트 O', () {
      final a = ApiErrorPolicy.decide(ApiErrorInfo(
          statusCode: 401, isAuthError: true, message: '만료', suppressToast: false));
      expect(a.clearAuthSession, isTrue);
      expect(a.showToast, isTrue);
    });

    test('silent + 403/404/500 → 세션정리 X · 토스트 X (화면이 처리)', () {
      for (final s in [403, 404, 500]) {
        final a = ApiErrorPolicy.decide(ApiErrorInfo(
            statusCode: s, isServerError: s >= 500, message: 'e', suppressToast: true));
        expect(a.clearAuthSession, isFalse, reason: '$s');
        expect(a.showToast, isFalse, reason: '$s');
        expect(a.markSuspended, isFalse, reason: '$s');
      }
    });

    test('non-silent + 일반 오류 → 토스트 O · 세션정리 X', () {
      final a = ApiErrorPolicy.decide(ApiErrorInfo(
          statusCode: 500, isServerError: true, message: 'e', suppressToast: false));
      expect(a.showToast, isTrue);
      expect(a.clearAuthSession, isFalse);
    });
  });
}
