// 2026-05-29 Phase B — 도감 API wrapper.

import '../../../core/network/api_client.dart';
import 'dex_models.dart';

class DexApi {
  /// 도감 메인 — default 40, max 60 backend-side 클램프 (2026-05-30 사용자 명시).
  static Future<DexMain> getDexMain({int limit = 40}) async {
    final res = await ApiClient.get('/api/assets/dex', params: {'limit': limit});
    final data = res['data'] as Map<String, dynamic>;
    return DexMain.fromJson(data);
  }

  /// 시리즈 상세 — 카드 list + 보유 여부 + 힛카드 4장.
  static Future<DexDetail> getDexDetail(String productId) async {
    final res = await ApiClient.get('/api/assets/dex/$productId');
    final data = res['data'] as Map<String, dynamic>;
    return DexDetail.fromJson(data);
  }
}
