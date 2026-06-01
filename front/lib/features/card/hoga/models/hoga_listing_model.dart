import 'hoga_board_model.dart';

/// 호가창 row 클릭 시 하단시트에 표시되는 등록자 한 명.
class HogaListing {
  final String userId;
  final String? nickname;
  final int price;
  final String? memo;
  final DateTime createdAt;
  final String? assetId;        // ASK 만
  final String? tradeId;        // ASK 만
  final String? buyOrderId;     // BID 만
  final String? tradeImageUrl;  // ASK 사용자 업로드 사진 (nullable)
  final String? tradeStatus;    // ASK 만: OPEN/RESERVED — 예약중 chip 표시용
  final int chatCount;          // ASK 만: 판매글 채팅방 수
  final int favoriteCount;      // ASK 만: 판매글 관심 수

  const HogaListing({
    required this.userId,
    required this.nickname,
    required this.price,
    required this.memo,
    required this.createdAt,
    required this.assetId,
    required this.tradeId,
    required this.buyOrderId,
    required this.tradeImageUrl,
    required this.tradeStatus,
    required this.chatCount,
    required this.favoriteCount,
  });

  factory HogaListing.fromJson(Map<String, dynamic> json) => HogaListing(
        userId: json['userId'] as String,
        nickname: json['nickname'] as String?,
        price: (json['price'] as num).toInt(),
        memo: json['memo'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        assetId: json['assetId'] as String?,
        tradeId: json['tradeId'] as String?,
        buyOrderId: json['buyOrderId'] as String?,
        tradeImageUrl: json['tradeImageUrl'] as String?,
        tradeStatus: json['tradeStatus'] as String?,
        chatCount: (json['chatCount'] as num?)?.toInt() ?? 0,
        favoriteCount: (json['favoriteCount'] as num?)?.toInt() ?? 0,
      );

  /// 채팅 자동 생성에 필요한 saleListingId (ASK일 때만 유효).
  String? get saleListingId => tradeId;
}

/// 호가 row(특정 가격) 등록자 리스트 응답.
class HogaListings {
  final String cardId;
  final HogaStatus status;
  final HogaSide side;
  final int price;
  final int totalCount;
  final List<HogaListing> listings;

  const HogaListings({
    required this.cardId,
    required this.status,
    required this.side,
    required this.price,
    required this.totalCount,
    required this.listings,
  });

  factory HogaListings.fromJson(Map<String, dynamic> json) => HogaListings(
        cardId: json['cardId'] as String,
        status: HogaStatus.fromWire(json['status'] as String),
        side: (json['side'] as String).toUpperCase() == 'ASK'
            ? HogaSide.ask
            : HogaSide.bid,
        price: (json['price'] as num).toInt(),
        totalCount: (json['totalCount'] as num).toInt(),
        listings: ((json['listings'] as List?) ?? [])
            .map((e) => HogaListing.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
