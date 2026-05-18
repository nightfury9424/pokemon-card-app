import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/hoga_board_model.dart';
import '../models/hoga_listing_model.dart';

/// 호가창 백엔드 API 클라이언트.
///
/// Endpoints (back/HogaController.java):
///   GET /api/cards/{cardId}/hoga?status=RAW&limit=5
///   GET /api/cards/{cardId}/hoga/{price}?status=RAW&side=ASK|BID
class HogaApi {
  HogaApi._();

  /// 호가창 (매도 N + 매수 N).
  static Future<HogaBoardData> fetchBoard(
    String cardId, {
    HogaStatus status = HogaStatus.raw,
    int limit = 5,
  }) async {
    final res = await ApiClient.get(
      '${ApiConstants.cards}/$cardId/hoga',
      params: {'status': status.wire, 'limit': '$limit'},
    );
    return HogaBoardData.fromJson(res);
  }

  /// 특정 가격 등록자 리스트 (하단시트).
  static Future<HogaListings> fetchListings(
    String cardId,
    int price, {
    HogaStatus status = HogaStatus.raw,
    required HogaSide side,
  }) async {
    final res = await ApiClient.get(
      '${ApiConstants.cards}/$cardId/hoga/$price',
      params: {'status': status.wire, 'side': side.wire},
    );
    return HogaListings.fromJson(res);
  }
}
