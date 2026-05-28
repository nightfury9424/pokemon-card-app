/// 가격 표시 라벨 매핑 — 가격 기준이 한국/해외/예상/없음인지 사용자에게 명확히 노출.
///
/// 백엔드 `koPriceLabelType` enum (PriceLabelType.java):
///  - `DOMESTIC_REAL` / `DOMESTIC_FEW` : 국내 실거래 기반 (domesticCount 배선 후 발화, 현재 stub)
///  - `ESTIMATED` : 해외 시세 기반 KO 예상 가치 (대다수 카드)
///  - `OVERSEAS_REF` : 해외 직접 참고가 (PROMO_DIRECT 등)
///
/// 출시 단계 매핑 사양:
///  - OVERSEAS_REF → "해외 참고가"  (이미 사용 중)
///  - ESTIMATED / KO_ESTIMATED / null + 가격 있음 → "국내 예상가"  ← 신규
///  - 가격 없음(null/0) → "시세 준비중"
///  - DOMESTIC_REAL/DOMESTIC_FEW → "국내 거래가" — 단 도메스틱 obs 배선되기 전엔 발화 안 함.
///    별도 cron(거래완료 batch)이 깔리면 자동으로 활성.
class PriceLabel {
  /// `labelType` = `koPriceLabelType` 값 (백엔드 enum 이름 그대로).
  /// `price` 가 null 또는 0이면 "시세 준비중" 우선.
  static String resolve({String? labelType, num? price}) {
    if (price == null || price <= 0) return '시세 준비중';
    switch (labelType) {
      case 'OVERSEAS_REF':
        return '해외 참고가';
      case 'DOMESTIC_REAL':
      case 'DOMESTIC_FEW':
        return '국내 거래가';
      case 'ESTIMATED':
      case 'KO_ESTIMATED':
      default:
        return '국내 예상가';
    }
  }

  /// labelType만으로 매핑 (가격 검사 없이) — 가격 separate 표시 시.
  static String resolveByType(String? labelType) {
    switch (labelType) {
      case 'OVERSEAS_REF':
        return '해외 참고가';
      case 'DOMESTIC_REAL':
      case 'DOMESTIC_FEW':
        return '국내 거래가';
      default:
        return '국내 예상가';
    }
  }
}
