import 'api_client.dart';

/// 전역 API 오류 대응 정책 — 순수 함수(테스트 가능). main.dart 의 setErrorHandler 가 이걸로
/// 결정한 뒤 부수효과(토스트/세션정리/게이트)를 실행한다.
///
/// 원칙:
/// - 인증·계정 lifecycle(401 세션 정리, USER_SUSPENDED 게이트)은 **silent 여부와 무관하게 항상** 수행.
/// - silent(suppressToast)은 **전역 토스트 '표시'만** 억제. 화면이 도메인 오류를 직접 처리.
class ApiErrorAction {
  /// 계정 정지 게이트로 이동(토스트 없음).
  final bool markSuspended;

  /// 인증 만료 → 토큰 폐기 + 세션 캐시 초기화 + 로그아웃 전환.
  final bool clearAuthSession;

  /// 전역 오류 토스트 표시.
  final bool showToast;

  const ApiErrorAction({
    this.markSuspended = false,
    this.clearAuthSession = false,
    this.showToast = false,
  });
}

class ApiErrorPolicy {
  static ApiErrorAction decide(ApiErrorInfo info) {
    // 계정 정지 — 게이트로(토스트 없음). lifecycle 이므로 suppressToast 무관.
    if (info.code == 'USER_SUSPENDED') {
      return const ApiErrorAction(markSuspended: true);
    }
    return ApiErrorAction(
      clearAuthSession: info.isAuthError, // 401 → 항상 세션 정리(silent 여도)
      showToast: !info.suppressToast,     // 표시만 silent 가 억제
    );
  }
}
