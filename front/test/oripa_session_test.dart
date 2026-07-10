import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';

/// Stage 2~3a: activeDraw 수명주기 / 중복 방지 / 래치 / 사전조건 / drawId-scoped
/// / typed outcome / immutable / revealStarted (spec §11·§B-6, 가드1·2).
void main() {
  final s = OripaSession.instance;
  final o1 = OripaMock.oripaById('o1'); // pricePerDraw 50000, 선두 47→9→52
  final o3 = OripaMock.oripaById('o3'); // 다른 오리파

  setUp(() => s.reset());

  String id() => s.activeDraw!.drawId;
  DrawCreated created(OripaProduct o) => s.confirmDraw(o) as DrawCreated;
  // 상품확인 CTA(revealStarted) → HERO 완료(REVEALED)
  void reveal(String drawId) {
    s.markRevealStarted(drawId);
    s.markRevealed(drawId);
  }

  DrawCreated drawReveal(OripaProduct o) {
    final c = created(o);
    reveal(c.drawId);
    return c;
  }

  test('1) commit 1회 → points 차감·taken·activeDraw(COMMITTED) 정확히 1회', () {
    final p0 = s.points;
    final c = created(o1);
    expect(c.number, 47);
    expect(s.points, p0 - o1.pricePerDraw);
    expect(s.isTaken(o1, 47), isTrue);
    final a = s.activeDraw!;
    expect(a.status, DrawStatus.committed);
    expect(a.revealStarted, isFalse);
    expect(a.revealDescriptor.openingHeader, '47번 당첨');
  });

  test('2) commit 연타(같은 오리파) → DrawAlreadyActive, 포인트 1회만', () {
    final p0 = s.points;
    final c1 = created(o1);
    final again = s.confirmDraw(o1);
    expect(again, isA<DrawAlreadyActive>());
    expect((again as DrawAlreadyActive).drawId, c1.drawId);
    expect(s.points, p0 - o1.pricePerDraw);
    expect(id(), c1.drawId);
  });

  test('3) COMMITTED/REVEALED 중 같은 오리파 새 draw 금지', () {
    final c = created(o1);
    reveal(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
    expect(s.confirmDraw(o1), isA<DrawAlreadyActive>());
    expect(id(), c.drawId);
  });

  test('4) markRevealed → REVEALED (revealStarted+committed에서만, 멱등)', () {
    final c = created(o1);
    s.markRevealStarted(c.drawId);
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
  });

  test('5) KEEP 또는 EXCHANGE 하나만 1회 → RESOLVED (다른 쪽 무시)', () {
    final c = created(o1);
    final held0 = s.heldTotalCount;
    reveal(c.drawId);
    s.keepPrize(c.drawId, 's1');
    expect(s.activeDraw!.status, DrawStatus.resolved);
    expect(s.activeDraw!.resolution, DrawResolution.keep);
    expect(s.heldTotalCount, held0 + 1);
    final pts = s.points;
    s.exchangePrize(c.drawId);
    expect(s.points, pts);
  });

  test('6) resolution 연타 → held/points 중복 반영 금지', () {
    final c1 = drawReveal(o1);
    final h0 = s.heldTotalCount;
    s.keepPrize(c1.drawId, 's1');
    s.keepPrize(c1.drawId, 's1');
    expect(s.heldTotalCount, h0 + 1);
    s.reset();
    final c2 = drawReveal(o1);
    final ex = s.activeDraw!.prize.exchangePoints;
    final p0 = s.points;
    s.exchangePrize(c2.drawId);
    s.exchangePrize(c2.drawId);
    expect(s.points, p0 + ex);
  });

  test('7) 돌아가기 → RESOLVED activeDraw clear (진행 중이면 유지)', () {
    final c = created(o1);
    s.clearActiveDraw(c.drawId); // COMMITTED → 유지
    expect(s.activeDraw, isNotNull);
    reveal(c.drawId);
    s.keepPrize(c.drawId, 's1');
    s.clearActiveDraw(c.drawId);
    expect(s.activeDraw, isNull);
  });

  test('8) 다시 뽑기 → 이전 RESOLVED를 새 COMMITTED로 원자 교체', () {
    final c1 = drawReveal(o1);
    s.keepPrize(c1.drawId, 's1');
    final c2 = created(o1);
    expect(c2.drawId, isNot(c1.drawId));
    expect(s.activeDraw!.status, DrawStatus.committed);
    expect(c1.number, 47);
    expect(c2.number, 9);
  });

  test('9) reset → activeDraw·points 초기화', () {
    created(o1);
    s.reset();
    expect(s.activeDraw, isNull);
    expect(s.points, OripaMock.pointBalance);
  });

  test('10) 다른 오리파 진행 중 draw도 전역 차단 → DrawRejected·무변경', () {
    final c = created(o1);
    final p0 = s.points;
    final r = s.confirmDraw(o3);
    expect(r, isA<DrawRejected>());
    expect((r as DrawRejected).reason, DrawFailure.drawInProgress);
    expect(s.points, p0);
    expect(id(), c.drawId);
  });

  test('11) COMMITTED에서 KEEP/EXCHANGE 차단(REVEALED에서만)', () {
    final c = created(o1);
    final h0 = s.heldTotalCount;
    final p0 = s.points;
    s.keepPrize(c.drawId, 's1');
    s.exchangePrize(c.drawId);
    expect(s.heldTotalCount, h0);
    expect(s.points, p0);
    expect(s.activeDraw!.status, DrawStatus.committed);
  });

  test('12) 포인트 부족 → DrawRejected(insufficientPoints), 무변경', () {
    var c = drawReveal(o1);
    s.keepPrize(c.drawId, 's1');
    c = drawReveal(o1);
    s.keepPrize(c.drawId, 's1');
    expect(s.points, lessThan(o1.pricePerDraw));
    final pts = s.points;
    final act = s.activeDraw;
    final r = s.confirmDraw(o1);
    expect(r, isA<DrawRejected>());
    expect((r as DrawRejected).reason, DrawFailure.insufficientPoints);
    expect(s.points, pts);
    expect(s.activeDraw, same(act));
  });

  test('13) 유효 번호 없음(빈 order) → DrawRejected(soldOut), 무변경', () {
    const empty = OripaProduct(
      oripaId: 'zz_empty', shopId: 's1', title: 't',
      pricePerDraw: 0, totalSlots: 1, remainingSlots: 1,
      type: OripaType.number, featuredPrizes: [],
    );
    final r = s.confirmDraw(empty);
    expect(r, isA<DrawRejected>());
    expect((r as DrawRejected).reason, DrawFailure.soldOut);
    expect(s.activeDraw, isNull);
  });

  test('14) 전역 차단 실패 후 taken/activeDraw 동일', () {
    final c = created(o1);
    s.confirmDraw(o3);
    s.confirmDraw(o1);
    expect(id(), c.drawId);
    expect(s.isTaken(o1, c.number), isTrue);
    expect(s.isTaken(o1, 9), isFalse);
  });

  test('15) 오래된 drawId 콜백은 새 draw를 오염하지 못함', () {
    final old = created(o1);
    reveal(old.drawId);
    s.keepPrize(old.drawId, 's1');
    s.clearActiveDraw(old.drawId);
    final fresh = created(o1);
    expect(fresh.drawId, isNot(old.drawId));
    final h0 = s.heldTotalCount;
    final p0 = s.points;
    // stale id로 시도 → 전부 무시
    s.markRevealStarted(old.drawId);
    s.markRevealed(old.drawId);
    expect(s.activeDraw!.status, DrawStatus.committed);
    expect(s.activeDraw!.revealStarted, isFalse);
    // 정상 id
    reveal(fresh.drawId);
    s.keepPrize(old.drawId, 's1'); // stale
    s.exchangePrize(old.drawId); // stale
    expect(s.heldTotalCount, h0);
    expect(s.points, p0);
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.keepPrize(fresh.drawId, 's1');
    expect(s.activeDraw!.status, DrawStatus.resolved);
  });

  test('16) 실패(빈 order)엔 notifyListeners 없음 = 내부 무변경', () {
    const empty = OripaProduct(
      oripaId: 'zz_empty2', shopId: 's1', title: 't',
      pricePerDraw: 0, totalSlots: 1, remainingSlots: 1,
      type: OripaType.number, featuredPrizes: [],
    );
    var notifs = 0;
    void listener() => notifs++;
    s.addListener(listener);
    final r = s.confirmDraw(empty);
    s.removeListener(listener);
    expect(r, isA<DrawRejected>());
    expect(notifs, 0);
    expect(s.activeDraw, isNull);
  });

  test('17) ActiveDraw immutable — 전이 시 새 객체 교체, 옛 참조 불변', () {
    final c = created(o1);
    final before = s.activeDraw!;
    expect(before.status, DrawStatus.committed);
    reveal(c.drawId);
    expect(before.status, DrawStatus.committed); // 옛 참조 그대로
    expect(s.activeDraw!.status, DrawStatus.revealed);
    expect(identical(before, s.activeDraw), isFalse);
  });

  test('18) revealStarted — 상품확인 탭 기록, drawId-scoped, 전이 보존', () {
    final c = created(o1);
    expect(s.activeDraw!.revealStarted, isFalse);
    s.markRevealStarted('draw_stale');
    expect(s.activeDraw!.revealStarted, isFalse);
    s.markRevealStarted(c.drawId);
    expect(s.activeDraw!.revealStarted, isTrue);
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.revealStarted, isTrue);
    expect(s.activeDraw!.status, DrawStatus.revealed);
  });

  test('19) revealStarted=false에서 markRevealed → COMMITTED 유지(CTA 미경유 차단)', () {
    final c = created(o1);
    expect(s.activeDraw!.revealStarted, isFalse);
    s.markRevealed(c.drawId); // CTA 안 거침 → 무시
    expect(s.activeDraw!.status, DrawStatus.committed);
    s.markRevealStarted(c.drawId);
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
  });
}
