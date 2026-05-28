/// 가격 표시 라벨 매핑 — 가격 기준이 한국판/해외판/예상/없음인지 사용자에게 명확히 노출.
///
/// 표기 정책: "국내" 대신 "**한국판**" 사용.
/// 이유: 포켓몬 TCG는 발매 언어판이 가격 결정자(일본판 SAR vs 한국판 SAR 격차 큼). 또한 일부 카드는
/// 한국판 이미지 미준비로 해외판 이미지가 fallback으로 표시되는데, "국내 예상가"라고만 하면
/// "일본판 카드의 국내 가격" 으로 오해 가능. "한국판" 이 제품(카드)의 발매판을 명시해 모호성 제거.
///
/// 백엔드 `koPriceLabelType` enum (PriceLabelType.java):
///  - `DOMESTIC_REAL` / `DOMESTIC_FEW` : 한국판 실거래 기반 (domesticCount 배선 후 발화, 현재 stub)
///  - `ESTIMATED` : 해외 시세 기반 한국판 예상 가치 (대다수 카드)
///  - `OVERSEAS_REF` : 해외 직접 참고가 (PROMO_DIRECT 등)
///
/// 매핑 사양:
///  - OVERSEAS_REF → "해외 참고가"
///  - ESTIMATED / KO_ESTIMATED / null + 가격 있음 → "한국판 예상가"
///  - 가격 없음(null/0) → "시세 준비중"
///  - DOMESTIC_REAL/DOMESTIC_FEW → "한국판 거래가" — domestic obs 배선되기 전엔 발화 안 함.
///    별도 cron(거래완료 batch, KST 00:05)이 깔리면 자동 활성.
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
        return '한국판 거래가';
      case 'ESTIMATED':
      case 'KO_ESTIMATED':
      default:
        return '한국판 예상가';
    }
  }

  /// labelType만으로 매핑 (가격 검사 없이) — 가격 separate 표시 시.
  static String resolveByType(String? labelType) {
    switch (labelType) {
      case 'OVERSEAS_REF':
        return '해외 참고가';
      case 'DOMESTIC_REAL':
      case 'DOMESTIC_FEW':
        return '한국판 거래가';
      default:
        return '한국판 예상가';
    }
  }

  /// ESTIMATED(한국판 예상가) 케이스에서 가격 영역에 함께 표시할 보조 안내문.
  /// 자산을 JP/EN 발매판으로 등록한 사용자도 같은 카드 상세를 보므로,
  /// 한국판 기준임을 명시 + JP/EN 탭 안내 + 해외판 이미지 fallback 가능성을 1단락으로.
  static const String estimatedDisclaimer =
      '한국판 기준 예상가입니다. 다른 발매판 시세는 JP/EN 탭에서 확인할 수 있습니다. '
      '이미지는 해외판 참고 이미지일 수 있습니다.';
}
