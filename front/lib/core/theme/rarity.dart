/// 한국 포카 시장 시세 기준 레어도 hierarchy (정점 → 일반).
/// PokeFolio는 고레어 카드만 다룸 — ACE/H/R/C/U 등 일반 레어도는 제외.
///
/// 2026-05-12 사용자 확정 순서:
/// - MUR/UR/SAR/AR/MA/BWR: 시세 최정점
/// - CSR/CHR/HR: 캐릭터/하이 레어
/// - SSR(→SR 인접)/SR: 묶음
/// - SM-P/RRR/RR: 고레어 하한
/// - PR/K/S: 끝 묶음 (한정 프로모 + Shiny K-version + 시크릿)
///
/// 백엔드 CardRepository의 SQL CASE도 같이 이 순서를 사용.
class AppRarity {
  /// 정점 → 일반 순서. UI 정렬 + chip 정렬 등에 사용.
  static const List<String> hierarchy = [
    'MUR',  // Master Ultra Rare
    'UR',   // Ultra Rare
    'SAR',  // Special Art Rare
    'AR',   // Art Rare
    'MA',   // Mega Art (메가에볼루션 ex 일러스트)
    'BWR',  // Black & White Rare
    'CSR',  // Character Super Rare
    'CHR',  // Character Rare
    'HR',   // High Rare
    'SSR',  // Super Special Rare (SR과 묶음)
    'SR',   // Super Rare
    'SM-P', // Sun & Moon Promo (구버전 한정)
    'RRR',  // Triple Rare
    'RR',   // Double Rare
    'PR',   // Promo — 한정판
    'K',    // 찬란한 시리즈 (Korean Shiny)
    'S',    // Secret / Shiny (시크릿 레어)
  ];

  /// 레어도 → rank (낮을수록 높은 등급). UNKNOWN은 99.
  static int rank(String? rarity) {
    if (rarity == null) return 99;
    final i = hierarchy.indexOf(rarity);
    return i >= 0 ? i : 99;
  }

  /// 정렬용 비교자 (asc=정점 우선).
  static int compare(String? a, String? b) => rank(a).compareTo(rank(b));
}
