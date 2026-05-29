import '../../core/auth/auth_state.dart';
import '../../core/network/api_client.dart';

/// 2026-05-29 admin Stage 0 — 백엔드 /api/admin/** 호출 client.
///
/// 정책:
///   - probeIsAdmin: 403 silent — Codex A 권장 그대로. ApiClient 의 global error toast 우회.
///   - 그 외 mutation API 는 호출자가 try/catch 로 직접 처리.
///   - AdminAllowlistFilter (백엔드) 가 비-admin 요청 403 → 클라는 메뉴 숨김.
class AdminApi {
  /// 앱 bootstrap / 로그인 직후 호출. 결과 AuthState.markAdminProbe 로 캐시.
  /// silent: true — global SnackBar interceptor 우회 (Codex Critical 2 — fire-and-forget probe).
  /// 네트워크 오류 등 모든 실패 케이스 false 보수적 처리.
  static Future<void> probeIsAdmin() async {
    try {
      final res = await ApiClient.get('/api/admin/whoami', silent: true);
      final data = (res['data'] as Map?)?.cast<String, dynamic>();
      final isAdmin = (data?['isAdmin'] as bool?) ?? false;
      AuthState.instance.markAdminProbe(isAdmin: isAdmin);
    } catch (_) {
      // 403 / 401 / 네트워크 / 기타 — silent 처리, false 캐시.
      AuthState.instance.markAdminProbe(isAdmin: false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // 신고 처리
  // ─────────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> listReports({
    String? status,
    String? targetType,
    int page = 0,
    int size = 20,
  }) async {
    final params = <String, dynamic>{
      'page': page,
      'size': size,
    };
    if (status != null) params['status'] = status;
    if (targetType != null) params['targetType'] = targetType;
    final res = await ApiClient.get('/api/admin/reports', params: params);
    return (res['data'] as Map).cast<String, dynamic>();
  }

  static Future<Map<String, dynamic>> updateReportStatus(
    String reportId, {
    required String status,
    String? adminMemo,
    String? resolutionAction,
  }) async {
    final res = await ApiClient.patch(
      '/api/admin/reports/$reportId/status',
      data: {
        'status': status,
        if (adminMemo != null) 'adminMemo': adminMemo,
        if (resolutionAction != null) 'resolutionAction': resolutionAction,
      },
    );
    return (res['data'] as Map).cast<String, dynamic>();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 사용자 검색 / 정지
  // ─────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> searchUsers(String q,
      {int size = 20}) async {
    final res = await ApiClient.get(
      '/api/admin/users/search',
      params: {'q': q, 'size': size},
    );
    final list = (res['data'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .toList();
  }

  static Future<Map<String, dynamic>> suspendUser(
    String userId,
    String reason,
  ) async {
    final res = await ApiClient.post(
      '/api/admin/users/$userId/suspend',
      {'reason': reason},
    );
    return (res['data'] as Map).cast<String, dynamic>();
  }

  static Future<Map<String, dynamic>> unsuspendUser(String userId) async {
    final res =
        await ApiClient.post('/api/admin/users/$userId/unsuspend', {});
    return (res['data'] as Map).cast<String, dynamic>();
  }

  // ─────────────────────────────────────────────────────────────────────
  // 거래글 admin 삭제
  // ─────────────────────────────────────────────────────────────────────

  static Future<void> deleteTradePost(String tradeId, String? reason) async {
    await ApiClient.delete(
      '/api/admin/trade-posts/$tradeId',
      data: reason != null ? {'reason': reason} : null,
    );
  }
}
