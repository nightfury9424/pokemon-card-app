/// STEP 2 오리파 상품(prize) mock — **포켓폴리오 카드 도메인과 완전 분리.**
/// 오리파 상품은 매장 사장님이 직접 등록/업로드하는 물건이다(미래엔 사장님 업로드 S3 URL).
/// 따라서 cards.card_id / card CDN / 카드 DB lookup / 시세·예상가 / naver 데이터 **전부 무관.**
/// STEP 2 mock은 독립 static 데이터. 상품 이미지 = 오리파 전용 local asset(assets/mock/oripa/*).
/// 미래엔 이 image 자리가 파트너센터 사장님 업로드 S3 URL로 교체. rarity 등 카드 도메인 필드 없음
/// (오리파 상품은 카드뿐 아니라 슬랩/박스/팩/굿즈까지 가능).
class OripaPrize {
  final String id;
  final String name;
  final String image; // 오리파 전용 mock asset path (미래: 사장님 업로드 S3 URL). 카드 CDN/card_id 아님.
  final int exchangePoints; // 사장님이 정하는 mock 값(플랫폼은 심사/보정 안 함)
  const OripaPrize({
    required this.id,
    required this.name,
    required this.image,
    required this.exchangePoints,
  });
}

/// 번호 오리파 draw/상품 결정론 데이터. (난수 없음, 애니 중 결정 없음)
class OripaDraw {
  const OripaDraw._();

  /// 8개 mock 상품 catalog — 여러 번호가 반복 매핑(사장님이 수량 넣듯).
  static const List<OripaPrize> catalog = [
    OripaPrize(id: 'charizard', name: '리자몽 ex SAR', image: 'assets/mock/oripa/item_01.png', exchangePoints: 280000),
    OripaPrize(id: 'pikachu', name: '피카츄 마스터볼', image: 'assets/mock/oripa/item_02.png', exchangePoints: 45000),
    OripaPrize(id: 'mew', name: '뮤 ex', image: 'assets/mock/oripa/item_03.png', exchangePoints: 18000),
    OripaPrize(id: 'paozen', name: '파오젠 ex', image: 'assets/mock/oripa/item_04.png', exchangePoints: 8000),
    OripaPrize(id: 'koraidon', name: '코라이돈 ex', image: 'assets/mock/oripa/item_05.png', exchangePoints: 5000),
    OripaPrize(id: 'rr_a', name: 'RR 세레나', image: 'assets/mock/oripa/item_06.png', exchangePoints: 2000),
    OripaPrize(id: 'rr_b', name: 'RR 마리', image: 'assets/mock/oripa/item_07.png', exchangePoints: 1500),
    OripaPrize(id: 'rr_c', name: 'RR 아이리스', image: 'assets/mock/oripa/item_08.png', exchangePoints: 1000),
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

  /// 번호 → 상품(결정론). 모든 번호가 실 상품. override 없으면 필러(catalog 3~7).
  static const Map<String, Map<int, int>> _override = {
    'o1': {47: 0, 9: 1, 52: 2, 88: 0, 5: 1, 100: 2},
    'o3': {13: 0, 41: 1, 77: 2},
    'o5': {7: 0, 50: 1, 88: 2},
  };

  static OripaPrize prizeForNumber(String oripaId, int n) {
    final ov = _override[oripaId]?[n];
    if (ov != null) return catalog[ov];
    return catalog[3 + (n % 5)];
  }
}
