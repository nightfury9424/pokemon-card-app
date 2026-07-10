/// 리빌 연출 프로토타입 fixture — **실제 draw 번호 매핑과 독립** (spec §B-7).
/// Stage 3 리빌 위젯 프리뷰 + 연출 구조 테스트 전용. 실제 카탈로그/번호(47=리자몽 등)를
/// 건드리지 않는다. 스펙 B-7의 예시(블래키/팽도리)가 여기에 대응.
///
/// ⚠️ Stage 3 시각검증 TODO: 현재 imageRef는 카드 mock 이미지 재사용.
/// BRG 10 슬랩·미개봉팩·굿즈는 **전용 mock 이미지**가 있어야 손맛 판정이 정확하다.
library;

import 'oripa_prizes.dart';

/// 스펙 B-7 대응 프로토타입 상품 3종. intensity는 RevealPolicy 임계에 맞춰 설정.
class RevealFixtures {
  const RevealFixtures._();

  /// RAW_NORMAL — 일반 RR (NORMAL 강도). clue 4.
  static const RawCardPrize rawNormal = RawCardPrize(
    id: 'fix_raw_normal',
    displayName: '가디안 ex',
    imageRef: ImageRef.asset('assets/mock/oripa/item_05.png'),
    exchangePoints: 3000, // < rareAt → NORMAL
    rarityCode: RarityCode.rr,
    setDisplayName: '스칼렛 ex',
  );

  /// RAW_HIT — SAR 히트 (HIT 강도). clue 4. RAW_NORMAL과 동일 비트 수, 강도만 ↑.
  static const RawCardPrize rawHit = RawCardPrize(
    id: 'fix_raw_hit',
    displayName: '블래키 ex',
    imageRef: ImageRef.asset('assets/mock/oripa/item_01.png'),
    exchangePoints: 150000, // hitAt..jackpotAt → HIT
    rarityCode: RarityCode.sar,
    setDisplayName: '테라스탈 페스타 ex',
  );

  /// GRADED_HIT — BRG 10 (HIT 강도). clue 5(COMPANY·GRADE·RARITY·SET·NAME).
  static const GradedCardPrize gradedHit = GradedCardPrize(
    id: 'fix_graded_hit',
    displayName: '팽도리',
    imageRef: ImageRef.asset('assets/mock/oripa/item_08.png'), // TODO: 실제 슬랩 이미지
    exchangePoints: 120000, // HIT
    gradingCompany: GradingCompany.brg,
    gradeValue: '10',
    rarityCode: RarityCode.ar,
    setDisplayName: '인페르노',
  );

  static const List<OripaPrize> all = [rawNormal, rawHit, gradedHit];
}
