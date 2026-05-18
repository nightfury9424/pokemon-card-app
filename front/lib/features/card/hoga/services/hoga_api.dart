import '../../../../core/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../models/hoga_board_model.dart';
import '../models/hoga_listing_model.dart';

/// 호가창 백엔드 API 클라이언트.
///
/// Endpoints (back/HogaController.java):
///   GET /api/cards/{cardId}/hoga?status=RAW
///   GET /api/cards/{cardId}/hoga?status=PSA&grade=10
///   GET /api/cards/{cardId}/hoga/{price}?status=PSA&grade=10&side=ASK
class HogaApi {
  HogaApi._();

  /// 호가창 (매도 N + 매수 N). PSA/BRG일 때 [grade] 필수.
  static Future<HogaBoardData> fetchBoard(
    String cardId, {
    HogaStatus status = HogaStatus.raw,
    HogaGrade? grade,
    int limit = 5,
  }) async {
    final params = <String, dynamic>{
      'status': status.wire,
      'limit': '$limit',
    };
    if (status.requiresGrade && grade != null) {
      params['grade'] = grade.wire;
    }
    final res = await ApiClient.get(
      '${ApiConstants.cards}/$cardId/hoga',
      params: params,
    );
    return HogaBoardData.fromJson(res);
  }

  /// 특정 가격 등록자 리스트 (하단시트).
  static Future<HogaListings> fetchListings(
    String cardId,
    int price, {
    HogaStatus status = HogaStatus.raw,
    HogaGrade? grade,
    required HogaSide side,
  }) async {
    final params = <String, dynamic>{
      'status': status.wire,
      'side': side.wire,
    };
    if (status.requiresGrade && grade != null) {
      params['grade'] = grade.wire;
    }
    final res = await ApiClient.get(
      '${ApiConstants.cards}/$cardId/hoga/$price',
      params: params,
    );
    return HogaListings.fromJson(res);
  }
}
