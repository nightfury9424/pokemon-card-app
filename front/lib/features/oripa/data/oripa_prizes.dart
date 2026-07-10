/// STEP 2 오리파 상품(prize) mock — **포켓폴리오 카드 도메인과 완전 분리.**
/// 오리파 상품 = 매장 사장님이 직접 등록/업로드하는 물건(미래엔 사장님 업로드 S3 URL).
/// cards.card_id / card CDN / 카드 DB lookup / 시세·예상가 / naver 데이터 **전부 무관.**
///
/// 2026-07-10: `sealed OripaPrize` 확정(GPT 리뷰 반영). 상품 종류별 서브타입이
/// 필수 리빌 속성을 **구조적으로 보장**(nullable/optional 없음). 리빌 프로파일은
/// `switch(prize)` 타입 패턴 매칭으로 결정(reveal_models.dart).
library;

/// 상품 이미지 참조 — asset(현 mock) | network(미래 사장님 S3). 카드 CDN/card_id 아님.
enum ImageRefKind { asset, network }

class ImageRef {
  final ImageRefKind kind;
  final String value;
  const ImageRef.asset(this.value) : kind = ImageRefKind.asset;
  const ImageRef.network(this.value) : kind = ImageRefKind.network;
  bool get isAsset => kind == ImageRefKind.asset;
}

/// 그레이딩 회사 — 전역 규칙: **PSA·BRG만** (CGC·BGS 금지). OTHER 없음.
enum GradingCompany { psa, brg }

extension GradingCompanyLabel on GradingCompany {
  String get label => switch (this) {
        GradingCompany.psa => 'PSA',
        GradingCompany.brg => 'BRG',
      };
}

/// 레어도 코드 — 자유텍스트(`SAR/sar/사르`) 혼입 방지 위해 enum 정규화.
enum RarityCode { rr, ar, sr, sar, ur, chr, csr, ssr }

extension RarityCodeLabel on RarityCode {
  String get label => switch (this) {
        RarityCode.rr => 'RR',
        RarityCode.ar => 'AR',
        RarityCode.sr => 'SR',
        RarityCode.sar => 'SAR',
        RarityCode.ur => 'UR',
        RarityCode.chr => 'CHR',
        RarityCode.csr => 'CSR',
        RarityCode.ssr => 'SSR',
      };
}

/// 오리파 상품 — **sealed**. 종류별 서브타입이 필수 필드를 구조적으로 보장.
/// 공통 필드만 base에 존재(카드 단서 필드는 서브타입에만 → nullable 모순 없음).
sealed class OripaPrize {
  final String id;
  final String displayName; // 최종 상품명 단일 진실원 (= NAME 단서)
  final ImageRef imageRef; // 사장님 업로드(현 mock asset). 카드 CDN/card_id 아님.
  final int exchangePoints; // 사장님이 정하는 mock 값(플랫폼은 심사/보정 안 함)
  const OripaPrize({
    required this.id,
    required this.displayName,
    required this.imageRef,
    required this.exchangePoints,
  });
}

/// RAW 카드 → NUMBERED_CONFIRM_RAW / SEALED_MYSTERY_RAW (clue: CONDITION·RARITY·SET·NAME)
final class RawCardPrize extends OripaPrize {
  final RarityCode rarityCode;
  final String setDisplayName;
  const RawCardPrize({
    required super.id,
    required super.displayName,
    required super.imageRef,
    required super.exchangePoints,
    required this.rarityCode,
    required this.setDisplayName,
  });
}

/// 그레이딩 카드 → NUMBERED_CONFIRM_GRADED (clue: COMPANY·GRADE·RARITY·SET·NAME)
final class GradedCardPrize extends OripaPrize {
  final GradingCompany gradingCompany;
  final String gradeValue; // "10" 등. 정규화 입력·display.
  final RarityCode rarityCode;
  final String setDisplayName;
  const GradedCardPrize({
    required super.id,
    required super.displayName,
    required super.imageRef,
    required super.exchangePoints,
    required this.gradingCompany,
    required this.gradeValue,
    required this.rarityCode,
    required this.setDisplayName,
  });
}

/// 미개봉 팩 → PACK_CONFIRM (clue: CATEGORY·NAME, 카드 단서 없음)
final class SealedPackPrize extends OripaPrize {
  const SealedPackPrize({
    required super.id,
    required super.displayName,
    required super.imageRef,
    required super.exchangePoints,
  });
}

/// 굿즈 → GOODS_CONFIRM (clue: CATEGORY·NAME, 카드 단서 없음)
final class GoodsPrize extends OripaPrize {
  const GoodsPrize({
    required super.id,
    required super.displayName,
    required super.imageRef,
    required super.exchangePoints,
  });
}

/// 번호 오리파 draw/상품 결정론 데이터. (난수 없음, 애니 중 결정 없음)
class OripaDraw {
  const OripaDraw._();

  /// mock 상품 catalog — 여러 번호가 반복 매핑(사장님이 수량 넣듯). 타입 다양성 포함.
  static const List<OripaPrize> catalog = [
    // 0~7: RAW 카드 (filler는 3~7 사용)
    RawCardPrize(id: 'charizard', displayName: '리자몽 ex', imageRef: ImageRef.asset('assets/mock/oripa/item_01.png'), exchangePoints: 280000, rarityCode: RarityCode.sar, setDisplayName: '흑염의 지배자'),
    RawCardPrize(id: 'pikachu', displayName: '피카츄 ex', imageRef: ImageRef.asset('assets/mock/oripa/item_02.png'), exchangePoints: 45000, rarityCode: RarityCode.ur, setDisplayName: '151'),
    RawCardPrize(id: 'mew', displayName: '뮤 ex', imageRef: ImageRef.asset('assets/mock/oripa/item_03.png'), exchangePoints: 18000, rarityCode: RarityCode.ur, setDisplayName: '151'),
    RawCardPrize(id: 'paozen', displayName: '파오젠 ex', imageRef: ImageRef.asset('assets/mock/oripa/item_04.png'), exchangePoints: 8000, rarityCode: RarityCode.sar, setDisplayName: '스노우 해저드'),
    RawCardPrize(id: 'koraidon', displayName: '코라이돈 ex', imageRef: ImageRef.asset('assets/mock/oripa/item_05.png'), exchangePoints: 5000, rarityCode: RarityCode.sar, setDisplayName: '스칼렛 ex'),
    RawCardPrize(id: 'rr_a', displayName: '세레나', imageRef: ImageRef.asset('assets/mock/oripa/item_06.png'), exchangePoints: 2000, rarityCode: RarityCode.rr, setDisplayName: '나이트 완더러'),
    RawCardPrize(id: 'rr_b', displayName: '마리', imageRef: ImageRef.asset('assets/mock/oripa/item_07.png'), exchangePoints: 1500, rarityCode: RarityCode.rr, setDisplayName: '트리플렛 비트'),
    RawCardPrize(id: 'rr_c', displayName: '아이리스', imageRef: ImageRef.asset('assets/mock/oripa/item_08.png'), exchangePoints: 1000, rarityCode: RarityCode.rr, setDisplayName: '배틀 파트너즈'),
    // 8: 그레이딩 카드 · 9: 미개봉 팩 · 10: 굿즈 (타입 다양성 — override로 노출)
    GradedCardPrize(id: 'graded_penguin', displayName: '팽도리', imageRef: ImageRef.asset('assets/mock/oripa/item_01.png'), exchangePoints: 120000, gradingCompany: GradingCompany.brg, gradeValue: '10', rarityCode: RarityCode.ar, setDisplayName: '인페르노'),
    SealedPackPrize(id: 'pack_151', displayName: '151 부스터 박스', imageRef: ImageRef.asset('assets/mock/oripa/item_02.png'), exchangePoints: 90000),
    GoodsPrize(id: 'goods_mat', displayName: '피카츄 플레이매트', imageRef: ImageRef.asset('assets/mock/oripa/item_03.png'), exchangePoints: 15000),
  ];

  /// o1(151 마스터볼) 초기 획득 37개 — 사용자 확정 흩뿌림 set.
  static const Set<int> _o1Taken = {
    1, 3, 7, 11, 14, 18, 20, 22, 24, 26, 29, 31, 33, 35, 37, 39, 41, 43, 45, 48,
    50, 54, 56, 58, 60, 62, 64, 67, 70, 72, 75, 78, 81, 84, 87, 91, 96,
  };

  /// 초기 획득 set — soldCount개(= STEP1 total-remaining). o1=고정, 그외 결정론 scatter.
  static Set<int> initialTaken(String oripaId, int total, int soldCount) {
    if (oripaId == 'o1') return {..._o1Taken};
    return _scatter(total, soldCount, oripaId == 'o5' ? 29 : 13);
  }

  static Set<int> _scatter(int total, int count, int seed) {
    final s = <int>{};
    var x = seed % total;
    const step = 7; // gcd(7,80)=gcd(7,100)=1 → 전수 순회
    while (s.length < count && s.length < total) {
      s.add((x % total) + 1);
      x += step;
    }
    return s;
  }

  /// draw 고정 순서(1~100 permutation). taken이면 skip. o1 선두 47→9→52 필수.
  static final Map<String, List<int>> _order = {
    'o1': [47, 9, 52, ...List<int>.generate(100, (i) => i + 1).where((n) => n != 47 && n != 9 && n != 52)],
    'o3': List<int>.generate(80, (i) => i + 1),
    'o5': List<int>.generate(100, (i) => i + 1),
  };
  static List<int> orderOf(String oripaId) => _order[oripaId] ?? const [];

  /// 번호 → 상품(결정론). 모든 번호가 실 상품. override 없으면 필러(catalog 3~7=RAW).
  static const Map<String, Map<int, int>> _override = {
    'o1': {47: 0, 9: 1, 52: 2, 88: 0, 5: 1, 100: 2, 18: 8, 30: 9, 60: 10},
    'o3': {13: 0, 41: 1, 77: 2, 55: 8},
    'o5': {7: 0, 50: 1, 88: 2, 33: 8, 66: 9},
  };

  static OripaPrize prizeForNumber(String oripaId, int n) {
    final ov = _override[oripaId]?[n];
    if (ov != null) return catalog[ov];
    return catalog[3 + (n % 5)];
  }
}
