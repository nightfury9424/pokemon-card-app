// 2026-05-29 Phase B — 도감 데이터 모델.
// 백엔드 /api/assets/dex + /api/assets/dex/{productId} 응답 JSON parse.

class DexBoxItem {
  final String productId;
  final String productName;
  final int totalKoVisible;
  final int ownedCount;
  final String? heroCardId;
  final String? heroCardName;
  final String? heroCardRarity;
  final String? heroCardImageUrl;
  final String? latestCardAt;

  DexBoxItem({
    required this.productId,
    required this.productName,
    required this.totalKoVisible,
    required this.ownedCount,
    this.heroCardId,
    this.heroCardName,
    this.heroCardRarity,
    this.heroCardImageUrl,
    this.latestCardAt,
  });

  double get progressRatio =>
      totalKoVisible <= 0 ? 0 : ownedCount / totalKoVisible;

  factory DexBoxItem.fromJson(Map<String, dynamic> j) => DexBoxItem(
        productId: j['productId'] as String,
        productName: j['productName'] as String? ?? '',
        totalKoVisible: (j['totalKoVisible'] as num?)?.toInt() ?? 0,
        ownedCount: (j['ownedCount'] as num?)?.toInt() ?? 0,
        heroCardId: j['heroCardId'] as String?,
        heroCardName: j['heroCardName'] as String?,
        heroCardRarity: j['heroCardRarity'] as String?,
        heroCardImageUrl: j['heroCardImageUrl'] as String?,
        latestCardAt: j['latestCardAt'] as String?,
      );
}

class DexMain {
  final List<DexBoxItem> products;
  final int totalProducts;
  final bool hasMore;
  final int ownedSeriesCount;
  final int totalOwnedCards;
  final int totalAvailableCards;

  DexMain({
    required this.products,
    required this.totalProducts,
    required this.hasMore,
    required this.ownedSeriesCount,
    required this.totalOwnedCards,
    required this.totalAvailableCards,
  });

  factory DexMain.fromJson(Map<String, dynamic> j) => DexMain(
        products: (j['products'] as List? ?? const [])
            .map((e) => DexBoxItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalProducts: (j['totalProducts'] as num?)?.toInt() ?? 0,
        hasMore: j['hasMore'] as bool? ?? false,
        ownedSeriesCount: (j['ownedSeriesCount'] as num?)?.toInt() ?? 0,
        totalOwnedCards: (j['totalOwnedCards'] as num?)?.toInt() ?? 0,
        totalAvailableCards: (j['totalAvailableCards'] as num?)?.toInt() ?? 0,
      );
}

class DexCard {
  final String cardId;
  final String name;
  final String? rarityCode;
  final String? collectionNumber;
  final String? imageUrl;
  final bool owned;
  final int quantity;

  DexCard({
    required this.cardId,
    required this.name,
    this.rarityCode,
    this.collectionNumber,
    this.imageUrl,
    required this.owned,
    required this.quantity,
  });

  factory DexCard.fromJson(Map<String, dynamic> j) => DexCard(
        cardId: j['cardId'] as String,
        name: j['name'] as String? ?? '',
        rarityCode: j['rarityCode'] as String?,
        collectionNumber: j['collectionNumber'] as String?,
        imageUrl: j['imageUrl'] as String?,
        owned: j['owned'] as bool? ?? false,
        quantity: (j['quantity'] as num?)?.toInt() ?? 0,
      );
}

class DexDetail {
  final String productId;
  final String productName;
  final int totalKoVisible;
  final int ownedCount;
  final List<DexCard> hits;
  final List<DexCard> cards;

  DexDetail({
    required this.productId,
    required this.productName,
    required this.totalKoVisible,
    required this.ownedCount,
    required this.hits,
    required this.cards,
  });

  double get progressRatio =>
      totalKoVisible <= 0 ? 0 : ownedCount / totalKoVisible;

  factory DexDetail.fromJson(Map<String, dynamic> j) => DexDetail(
        productId: j['productId'] as String,
        productName: j['productName'] as String? ?? '',
        totalKoVisible: (j['totalKoVisible'] as num?)?.toInt() ?? 0,
        ownedCount: (j['ownedCount'] as num?)?.toInt() ?? 0,
        hits: (j['hits'] as List? ?? const [])
            .map((e) => DexCard.fromJson(e as Map<String, dynamic>))
            .toList(),
        cards: (j['cards'] as List? ?? const [])
            .map((e) => DexCard.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
