import 'package:flutter/foundation.dart';

/// STEP 1 오리파 mock 도메인 — 화면 성립에 필요한 최소 관계만 담는다.
/// ★백엔드 스키마 선설계 아님. 실제 DB/API/포인트 원장/추첨/배송은 이후 단계.
/// 모든 값은 하드코딩 mock이며 영속되지 않는다.

/// 포인트 표기 — 콤마 + " P". (원화 아님, 오리파 전용 재화)
String formatPoint(int p) {
  final s = p.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  return '$s P';
}

/// 오리파 2종 — STEP 1은 라벨/칩 구분까지만. 개봉 인터랙션은 이후 단계.
enum OripaType { number, sealed }

extension OripaTypeMeta on OripaType {
  String get label => switch (this) {
        OripaType.number => '번호 오리파',
        OripaType.sealed => '상품 봉인',
      };
}

@immutable
class OripaShop {
  final String shopId;
  final String shopName;
  final String area;
  final int freeShippingThreshold; // 무료배송 기준 P
  final int shippingAccruedP; // 이 매장에 현재 쌓인 배송 적립 P (mock)
  const OripaShop({
    required this.shopId,
    required this.shopName,
    required this.area,
    required this.freeShippingThreshold,
    required this.shippingAccruedP,
  });

  int get shippingRemaining =>
      (freeShippingThreshold - shippingAccruedP).clamp(0, freeShippingThreshold);
  bool get freeShippingReached => shippingRemaining <= 0;
}

@immutable
class OripaProduct {
  final String oripaId;
  final String shopId;
  final String title;
  final int pricePerDraw; // 1구 가격 P
  final int totalSlots;
  final int remainingSlots;
  final OripaType type;
  final List<String> featuredPrizes; // 상품판 투명성 — 대표 상품
  const OripaProduct({
    required this.oripaId,
    required this.shopId,
    required this.title,
    required this.pricePerDraw,
    required this.totalSlots,
    required this.remainingSlots,
    required this.type,
    required this.featuredPrizes,
  });

  int get soldSlots => totalSlots - remainingSlots;
  double get soldFraction => totalSlots == 0 ? 0 : soldSlots / totalSlots;
}

@immutable
class HeldItem {
  final String itemId;
  final String shopId;
  final String name;
  final String rarity;
  final int exchangePoints; // 교환 시 받는 P
  const HeldItem({
    required this.itemId,
    required this.shopId,
    required this.name,
    required this.rarity,
    required this.exchangePoints,
  });
}

/// in-memory mock 데이터 소스. (관계: HeldItem/OripaProduct.shopId → OripaShop)
class OripaMock {
  const OripaMock._();

  static const int pointBalance = 125000;

  static const List<OripaShop> shops = [
    OripaShop(shopId: 's1', shopName: '몬스터카드 홍대점', area: '서울 마포', freeShippingThreshold: 50000, shippingAccruedP: 32000),
    OripaShop(shopId: 's2', shopName: '카드월드 강남점', area: '서울 강남', freeShippingThreshold: 30000, shippingAccruedP: 35000),
    OripaShop(shopId: 's3', shopName: '플러스카드 부산점', area: '부산 부산진', freeShippingThreshold: 40000, shippingAccruedP: 8000),
  ];

  static const List<OripaProduct> oripas = [
    OripaProduct(oripaId: 'o1', shopId: 's1', title: '151 마스터볼 넘버 오리파', pricePerDraw: 50000, totalSlots: 100, remainingSlots: 63, type: OripaType.number, featuredPrizes: ['리자몽 ex SAR', '뮤츠 ex SAR', '피카츄 프로모']),
    OripaProduct(oripaId: 'o2', shopId: 's1', title: '스페셜 슬랩 봉인 오리파', pricePerDraw: 30000, totalSlots: 60, remainingSlots: 12, type: OripaType.sealed, featuredPrizes: ['PSA10 리자몽', 'PSA9 뮤']),
    OripaProduct(oripaId: 'o3', shopId: 's2', title: '이브이 히어로즈 넘버', pricePerDraw: 40000, totalSlots: 80, remainingSlots: 41, type: OripaType.number, featuredPrizes: ['샤미드 ex', '님피아 UR', '부스터 ex']),
    OripaProduct(oripaId: 'o4', shopId: 's2', title: '하이클래스 팩 봉인', pricePerDraw: 25000, totalSlots: 50, remainingSlots: 8, type: OripaType.sealed, featuredPrizes: ['미개봉 BOX', 'SAR 확정 팩']),
    OripaProduct(oripaId: 'o5', shopId: 's3', title: '테라스탈 페스타 넘버', pricePerDraw: 35000, totalSlots: 100, remainingSlots: 77, type: OripaType.number, featuredPrizes: ['테라파고스 ex', '가브리아스 ex', '루카리오 ex']),
  ];

  static const List<HeldItem> heldItems = [
    HeldItem(itemId: 'h1', shopId: 's1', name: '리자몽 ex', rarity: 'SAR', exchangePoints: 180000),
    HeldItem(itemId: 'h2', shopId: 's1', name: '이브이', rarity: 'UR', exchangePoints: 42000),
    HeldItem(itemId: 'h3', shopId: 's1', name: '뮤츠 ex', rarity: 'SR', exchangePoints: 28000),
    HeldItem(itemId: 'h4', shopId: 's1', name: '파이리', rarity: 'AR', exchangePoints: 12000),
    HeldItem(itemId: 'h5', shopId: 's1', name: '꼬부기', rarity: 'AR', exchangePoints: 9000),
    HeldItem(itemId: 'h6', shopId: 's2', name: '갸라도스', rarity: 'SSR', exchangePoints: 65000),
    HeldItem(itemId: 'h7', shopId: 's2', name: '잠만보', rarity: 'CHR', exchangePoints: 22000),
    HeldItem(itemId: 'h8', shopId: 's2', name: '뮤', rarity: 'CSR', exchangePoints: 33000),
  ];

  // ── 관계 헬퍼 (매장별 그룹) ──
  static OripaShop shopById(String id) => shops.firstWhere((s) => s.shopId == id);
  static OripaProduct oripaById(String id) => oripas.firstWhere((o) => o.oripaId == id);
  static List<OripaProduct> oripasByShop(String shopId) => oripas.where((o) => o.shopId == shopId).toList();
  static int activeOripaCount(String shopId) => oripasByShop(shopId).length;
  static List<HeldItem> heldByShop(String shopId) => heldItems.where((h) => h.shopId == shopId).toList();
  static int heldExchangeSum(String shopId) => heldByShop(shopId).fold(0, (s, h) => s + h.exchangePoints);
  static int get heldTotalCount => heldItems.length;
  static int get activeOripaTotal => oripas.length;

  /// 보관 상품이 있는 매장만 (홈 보관함 요약용)
  static List<OripaShop> get shopsWithHeld =>
      shops.where((s) => heldByShop(s.shopId).isNotEmpty).toList();
}
