import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_prizes.dart';
import 'package:front/features/oripa/data/reveal_models.dart';
import 'package:front/features/oripa/data/reveal_fixtures.dart';

void main() {
  group('sealed OripaPrize catalog', () {
    test('catalog 전부 유효 생성 + 타입 다양성 존재', () {
      expect(OripaDraw.catalog, isNotEmpty);
      expect(OripaDraw.catalog.whereType<RawCardPrize>(), isNotEmpty);
      expect(OripaDraw.catalog.whereType<GradedCardPrize>(), isNotEmpty);
      expect(OripaDraw.catalog.whereType<SealedPackPrize>(), isNotEmpty);
      expect(OripaDraw.catalog.whereType<GoodsPrize>(), isNotEmpty);
    });

    test('§4 최소 고정 매핑 유지 (o1: 47/9/52)', () {
      expect(OripaDraw.prizeForNumber('o1', 47).displayName, '리자몽 ex');
      expect(OripaDraw.prizeForNumber('o1', 9).displayName, '피카츄 ex');
      expect(OripaDraw.prizeForNumber('o1', 52).displayName, '뮤 ex');
    });

    test('모든 번호가 실 상품(placeholder 없음)', () {
      for (final n in OripaDraw.orderOf('o1')) {
        expect(OripaDraw.prizeForNumber('o1', n), isA<OripaPrize>());
      }
    });
  });

  group('RevealDescriptor 파생 (번호 오리파=확정형)', () {
    test('RAW → numberedConfirmRaw, clue 4개(CONDITION·RARITY·SET·NAME), 헤더', () {
      const p = RawCardPrize(
        id: 'x', displayName: '블래키 ex',
        imageRef: ImageRef.asset('a.png'), exchangePoints: 280000,
        rarityCode: RarityCode.sar, setDisplayName: '테라스탈 페스타 ex',
      );
      final d = buildRevealDescriptor(p, number: 47);
      expect(d.profile, RevealProfile.numberedConfirmRaw);
      expect(d.openingHeader, '47번 당첨');
      expect(d.clueBeatCount, 4);
      expect(d.clues.map((c) => c.kind), [
        RevealClueKind.condition, RevealClueKind.rarity,
        RevealClueKind.set, RevealClueKind.name,
      ]);
      expect(d.clues[0].text, 'RAW');
      expect(d.clues[1].text, 'SAR');
      expect(d.clues[3].text, '블래키 ex');
    });

    test('GRADED → numberedConfirmGraded, clue 5개(COMPANY·GRADE·RARITY·SET·NAME)', () {
      const p = GradedCardPrize(
        id: 'g', displayName: '팽도리',
        imageRef: ImageRef.asset('a.png'), exchangePoints: 120000,
        gradingCompany: GradingCompany.brg, gradeValue: '10',
        rarityCode: RarityCode.ar, setDisplayName: '인페르노',
      );
      final d = buildRevealDescriptor(p, number: 18);
      expect(d.profile, RevealProfile.numberedConfirmGraded);
      expect(d.clueBeatCount, 5);
      expect(d.clues.map((c) => c.text).toList(),
          ['BRG', '10', 'AR', '인페르노', '팽도리']);
    });

    test('PACK/GOODS → 2 clue(CATEGORY·NAME), 카드 단서 없음', () {
      const pack = SealedPackPrize(id: 'pk', displayName: '151 박스', imageRef: ImageRef.asset('a.png'), exchangePoints: 90000);
      const goods = GoodsPrize(id: 'gd', displayName: '플레이매트', imageRef: ImageRef.asset('a.png'), exchangePoints: 15000);
      final dp = buildRevealDescriptor(pack, number: 30);
      final dg = buildRevealDescriptor(goods, number: 60);
      expect(dp.profile, RevealProfile.packConfirm);
      expect(dp.clueBeatCount, 2);
      expect(dp.clues.last.text, '151 박스');
      expect(dg.profile, RevealProfile.goodsConfirm);
      expect(dg.clueBeatCount, 2);
    });

    test('봉인형(number=null) → mystery 프로파일 + 헤더 없음', () {
      const p = RawCardPrize(id: 'x', displayName: 'n', imageRef: ImageRef.asset('a.png'), exchangePoints: 1000, rarityCode: RarityCode.rr, setDisplayName: 's');
      final d = buildRevealDescriptor(p);
      expect(d.profile, RevealProfile.sealedMysteryRaw);
      expect(d.openingHeader, isNull);
    });
  });

  group('불변식: profile 내 clue 비트 수 고정', () {
    test('모든 RAW catalog 상품은 clue 4개 (NORMAL/HIT 무관)', () {
      for (final p in OripaDraw.catalog.whereType<RawCardPrize>()) {
        expect(buildRevealDescriptor(p, number: 1).clueBeatCount, 4);
      }
    });
    test('모든 GRADED catalog 상품은 clue 5개', () {
      for (final p in OripaDraw.catalog.whereType<GradedCardPrize>()) {
        expect(buildRevealDescriptor(p, number: 1).clueBeatCount, 5);
      }
    });
  });

  group('RevealPolicy: 교환P 임계 → intensity (효과만, 비트 수 불변)', () {
    const pol = RevealPolicy();
    test('임계 경계값', () {
      expect(pol.intensityFor(0), RevealIntensity.normal);
      expect(pol.intensityFor(RevealPolicy.rareAt), RevealIntensity.rare);
      expect(pol.intensityFor(RevealPolicy.hitAt), RevealIntensity.hit);
      expect(pol.intensityFor(RevealPolicy.jackpotAt), RevealIntensity.jackpot);
    });
    test('effectsEnabled=false → 항상 normal(강도 비활성)', () {
      const off = RevealPolicy(effectsEnabled: false);
      expect(off.intensityFor(500000), RevealIntensity.normal);
    });
    test('maxIntensity 캡', () {
      const capped = RevealPolicy(maxIntensity: RevealIntensity.rare);
      expect(capped.intensityFor(500000), RevealIntensity.rare);
    });
    test('NORMAL vs HIT라도 clue 비트 수는 동일 (강도만 차등)', () {
      const cheap = RawCardPrize(id: 'c', displayName: 'c', imageRef: ImageRef.asset('a.png'), exchangePoints: 1000, rarityCode: RarityCode.rr, setDisplayName: 's');
      const dear = RawCardPrize(id: 'd', displayName: 'd', imageRef: ImageRef.asset('a.png'), exchangePoints: 280000, rarityCode: RarityCode.sar, setDisplayName: 's');
      final dc = buildRevealDescriptor(cheap, number: 1);
      final dd = buildRevealDescriptor(dear, number: 1);
      expect(dc.intensity, RevealIntensity.normal);
      expect(dd.intensity, RevealIntensity.jackpot);
      expect(dc.clueBeatCount, dd.clueBeatCount); // 강도 달라도 비트 수 동일
    });
  });

  group('데모 상품 draw 가능성 (override 번호 un-taken)', () {
    test('o1 Graded/Pack/Goods 번호는 초기 taken에 없어 draw 가능', () {
      final taken = OripaDraw.initialTaken('o1', 100, 37);
      for (final n in [53, 30, 61]) {
        expect(taken.contains(n), isFalse,
            reason: '$n번이 taken이면 해당 상품이 draw로 안 나옴');
      }
    });
    test('o1 데모 번호 → 기대 타입', () {
      expect(OripaDraw.prizeForNumber('o1', 53), isA<GradedCardPrize>());
      expect(OripaDraw.prizeForNumber('o1', 30), isA<SealedPackPrize>());
      expect(OripaDraw.prizeForNumber('o1', 61), isA<GoodsPrize>());
    });
  });

  group('리빌 프로토타입 fixture (실제 draw와 독립)', () {
    test('RAW_HIT fixture → RAW·SAR·테라스탈·블래키, HIT 강도', () {
      final d = buildRevealDescriptor(RevealFixtures.rawHit, number: 47);
      expect(d.profile, RevealProfile.numberedConfirmRaw);
      expect(d.clues.map((c) => c.text).toList(),
          ['RAW', 'SAR', '테라스탈 페스타 ex', '블래키 ex']);
      expect(d.intensity, RevealIntensity.hit);
    });
    test('GRADED_HIT fixture → BRG·10·AR·인페르노·팽도리', () {
      final d = buildRevealDescriptor(RevealFixtures.gradedHit, number: 18);
      expect(d.profile, RevealProfile.numberedConfirmGraded);
      expect(d.clues.map((c) => c.text).toList(),
          ['BRG', '10', 'AR', '인페르노', '팽도리']);
      expect(d.intensity, RevealIntensity.hit);
    });
    test('RAW_NORMAL fixture → clue 4개, NORMAL 강도 (RAW_HIT와 비트 수 동일)', () {
      final n = buildRevealDescriptor(RevealFixtures.rawNormal, number: 1);
      final h = buildRevealDescriptor(RevealFixtures.rawHit, number: 1);
      expect(n.clueBeatCount, 4);
      expect(n.clueBeatCount, h.clueBeatCount);
      expect(n.intensity, RevealIntensity.normal);
    });
  });
}
