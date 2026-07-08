/// STEP 2 오리파 상품(prize) mock. 카드 DB/자산 도메인과 분리 — static 데이터만.
/// imageUrl은 실 카드 CDN URL(디코레이션 mock, card_id FK/DB lookup 아님).
/// ⚠️ sandbox에서 200 검증 불가 → 실기기 확인 필요. 안 뜨면 CardImage가 카드뒷면 degrade.
class OripaPrize {
  final String id;
  final String name;
  final String rarity;
  final String imageUrl;
  final int exchangePoints;
  const OripaPrize({
    required this.id,
    required this.name,
    required this.rarity,
    required this.imageUrl,
    required this.exchangePoints,
  });
}

/// 번호 오리파 draw/상품 결정론 데이터. (난수 없음, 애니 중 결정 없음)
class OripaDraw {
  const OripaDraw._();

  /// 8개 mock 상품 카탈로그 — 여러 번호가 반복 매핑(사장님이 수량 넣듯).
  static const List<OripaPrize> catalog = [
    OripaPrize(id: 'charizard', name: '리자몽 ex', rarity: 'SAR', exchangePoints: 280000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_00182F81CA884726A6BB.png'),
    OripaPrize(id: 'pikachu', name: '피카츄 마스터볼', rarity: 'CHR', exchangePoints: 45000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_00C3F08C0B7C41B1A2DA.png'),
    OripaPrize(id: 'mew', name: '뮤 ex', rarity: 'UR', exchangePoints: 18000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_01E1A15D9BF64FB3A102.png'),
    OripaPrize(id: 'paozen', name: '파오젠 ex', rarity: 'SR', exchangePoints: 8000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_0320E0D5056F4FBDB33A.png'),
    OripaPrize(id: 'koraidon', name: '코라이돈 ex', rarity: 'AR', exchangePoints: 5000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_0512DE9EF51D4BE39554.png'),
    OripaPrize(id: 'rr_a', name: 'RR 세레나', rarity: 'RR', exchangePoints: 2000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_06CEAC2A8B35426D926A.png'),
    OripaPrize(id: 'rr_b', name: 'RR 마리', rarity: 'RR', exchangePoints: 1500, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_09516DD8E2C14A009B0E.png'),
    OripaPrize(id: 'rr_c', name: 'RR 아이리스', rarity: 'RR', exchangePoints: 1000, imageUrl: 'https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/CRD_0C103A2D31494C7580E2.png'),
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

  /// chase(명명상품) override — 모두 초기 미획득 번호. 상품판 강조/투명성용.
  static const Map<String, Map<int, int>> _override = {
    'o1': {47: 0, 9: 1, 52: 2, 88: 0, 5: 1, 100: 2},
    'o3': {13: 0, 41: 1, 77: 2},
    'o5': {7: 0, 50: 1, 88: 2},
  };

  /// 번호 → 상품(결정론). 모든 번호가 실 상품. override 없으면 필러(catalog 3~7).
  static OripaPrize prizeForNumber(String oripaId, int n) {
    final ov = _override[oripaId]?[n];
    if (ov != null) return catalog[ov];
    return catalog[3 + (n % 5)];
  }

  /// 상품판에서 chase 번호인지(강조용).
  static bool isChase(String oripaId, int n) =>
      _override[oripaId]?.containsKey(n) ?? false;
}
