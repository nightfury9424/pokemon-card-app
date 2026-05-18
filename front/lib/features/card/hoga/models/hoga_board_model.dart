/// 호가창 상태 필터 (back HogaStatus와 1:1).
enum HogaStatus {
  raw('RAW'),
  psa10('PSA10'),
  brg('BRG');

  final String wire;
  const HogaStatus(this.wire);

  static HogaStatus fromWire(String s) =>
      HogaStatus.values.firstWhere(
        (e) => e.wire == s.toUpperCase(),
        orElse: () => HogaStatus.raw,
      );

  String get label => switch (this) {
        HogaStatus.raw => 'RAW',
        HogaStatus.psa10 => 'PSA 10',
        HogaStatus.brg => 'BRG',
      };
}

/// ASK = 매도(파랑) / BID = 매수(초록).
enum HogaSide {
  ask('ASK'),
  bid('BID');

  final String wire;
  const HogaSide(this.wire);
}

/// 호가창 한 행 — 가격 + 등록 건수 + 잔량 막대 비율.
class HogaLevel {
  final int price;
  final int count;
  final double barRatio;

  const HogaLevel({
    required this.price,
    required this.count,
    required this.barRatio,
  });

  factory HogaLevel.fromJson(Map<String, dynamic> json) => HogaLevel(
        price: (json['price'] as num).toInt(),
        count: (json['count'] as num).toInt(),
        barRatio: ((json['barRatio'] as num?) ?? 0).toDouble(),
      );
}

/// 호가창 전체 응답.
class HogaBoardData {
  final String cardId;
  final HogaStatus status;
  final int tickUnit;
  final int? marketPrice;
  final int? lowestAsk;
  final int? highestBid;
  final int askCount;
  final int bidCount;
  final List<HogaLevel> asks;
  final List<HogaLevel> bids;

  const HogaBoardData({
    required this.cardId,
    required this.status,
    required this.tickUnit,
    required this.marketPrice,
    required this.lowestAsk,
    required this.highestBid,
    required this.askCount,
    required this.bidCount,
    required this.asks,
    required this.bids,
  });

  bool get isEmpty => askCount == 0 && bidCount == 0;

  factory HogaBoardData.fromJson(Map<String, dynamic> json) => HogaBoardData(
        cardId: json['cardId'] as String,
        status: HogaStatus.fromWire(json['status'] as String),
        tickUnit: (json['tickUnit'] as num).toInt(),
        marketPrice: (json['marketPrice'] as num?)?.toInt(),
        lowestAsk: (json['lowestAsk'] as num?)?.toInt(),
        highestBid: (json['highestBid'] as num?)?.toInt(),
        askCount: (json['askCount'] as num).toInt(),
        bidCount: (json['bidCount'] as num).toInt(),
        asks: ((json['asks'] as List?) ?? [])
            .map((e) => HogaLevel.fromJson(e as Map<String, dynamic>))
            .toList(),
        bids: ((json['bids'] as List?) ?? [])
            .map((e) => HogaLevel.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
