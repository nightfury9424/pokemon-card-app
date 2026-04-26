class CardModel {
  final String cardId;
  final String name;
  final String rarityCode;
  final String collectionNumber;
  final String? localImagePath;
  final String? setName;

  const CardModel({
    required this.cardId,
    required this.name,
    required this.rarityCode,
    required this.collectionNumber,
    this.localImagePath,
    this.setName,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      cardId: json['cardId'] ?? '',
      name: json['name'] ?? '',
      rarityCode: json['rarityCode'] ?? '',
      collectionNumber: json['collectionNumber'] ?? '',
      localImagePath: json['localImagePath'],
      setName: json['setName'],
    );
  }
}

class PriceSnapshotModel {
  final String source;
  final int price;
  final String cardStatus;
  final String? gradingCompany;
  final String? gradeValue;
  final String tradedAt;

  const PriceSnapshotModel({
    required this.source,
    required this.price,
    required this.cardStatus,
    this.gradingCompany,
    this.gradeValue,
    required this.tradedAt,
  });

  factory PriceSnapshotModel.fromJson(Map<String, dynamic> json) {
    return PriceSnapshotModel(
      source: json['source'] ?? '',
      price: json['price'] ?? 0,
      cardStatus: json['cardStatus'] ?? 'RAW',
      gradingCompany: json['gradingCompany'],
      gradeValue: json['gradeValue'],
      tradedAt: json['tradedAt'] ?? '',
    );
  }

  String get sourceLabel {
    switch (source) {
      case 'ICU': return '너정다';
      case 'NAVER_SHOPPING': return '네이버쇼핑';
      case 'APP': return '앱 거래';
      default: return source;
    }
  }

  String get priceFormatted {
    if (price >= 10000) {
      return '${(price / 10000).toStringAsFixed(price % 10000 == 0 ? 0 : 1)}만원';
    }
    return '${price.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}원';
  }
}
