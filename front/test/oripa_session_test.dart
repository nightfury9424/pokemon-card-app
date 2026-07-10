import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';

/// Stage 2~3a: activeDraw 수명주기 / 중복 방지 / 래치 / 사전조건 / drawId-scoped
/// / typed outcome / immutable (spec §11·§B-6, 가드1·2).
void main() {
  final s = OripaSession.instance;
  final o1 = OripaMock.oripaById('o1'); // pricePerDraw 50000, 선두 47→9→52
  final o3 = OripaMock.oripaById('o3'); // 다른 오리파(다른 매장)

  setUp(() => s.reset());

  String id() => s.activeDraw!.drawId;
  DrawCreated created(OripaProduct o) => s.confirmDraw(o) as DrawCreated;
  DrawCreated drawReveal(OripaProduct o) {
    final c = created(o);
    s.markRevealed(c.drawId);
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
    expect(a.number, 47);
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
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
    expect(s.confirmDraw(o1), isA<DrawAlreadyActive>());
    expect(id(), c.drawId);
  });

  test('4) hero 완료 → REVEALED 전이 (committed에서만, 멱등)', () {
    final c = created(o1);
    expect(s.activeDraw!.status, DrawStatus.committed);
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.markRevealed(c.drawId);
    expect(s.activeDraw!.status, DrawStatus.revealed);
  });

  test('5) KEEP 또는 EXCHANGE 하나만 1회 → RESOLVED (다른 쪽 무시)', () {
    final c = created(o1);
    final held0 = s.heldTotalCount;
    s.markRevealed(c.drawId);
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
    s.markRevealed(c.drawId);
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
    expect(s.activeDraw, isNotNull);
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
    expect(s.isTaken(o3, s.activeDraw!.number), isFalse);
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
    final rem = s.remaining(o1);
    final act = s.activeDraw;
    final r = s.confirmDraw(o1);
    expect(r, isA<DrawRejected>());
    expect((r as DrawRejected).reason, DrawFailure.insufficientPoints);
    expect(s.points, pts);
    expect(s.remaining(o1), rem);
    expect(s.activeDraw, same(act));
  });

  test('13) 유효 번호 없음(빈 order) → DrawRejected(soldOut), 무변경', () {
    const empty = OripaProduct(
      oripaId: 'zz_empty', shopId: 's1', title: 't',
      pricePerDraw: 0, totalSlots: 1, remainingSlots: 1,
      type: OripaType.number, featuredPrizes: [],
    );
    final p0 = s.points;
    final r = s.confirmDraw(empty);
    expect(r, isA<DrawRejected>());
    expect((r as DrawRejected).reason, DrawFailure.soldOut);
    expect(s.points, p0);
    expect(s.activeDraw, isNull);
  });

  test('14) 전역 차단 실패 후 taken/activeDraw 동일', () {
    final c = created(o1);
    s.confirmDraw(o3); // 전역 차단
    s.confirmDraw(o1); // alreadyActive
    expect(id(), c.drawId);
    expect(s.isTaken(o1, c.number), isTrue);
    expect(s.isTaken(o1, 9), isFalse);
  });

  test('15) 오래된 drawId 콜백은 새 draw를 오염하지 못함', () {
    final old = created(o1);
    s.markRevealed(old.drawId);
    s.keepPrize(old.drawId, 's1');
    s.clearActiveDraw(old.drawId);
    final fresh = created(o1);
    expect(fresh.drawId, isNot(old.drawId));
    final h0 = s.heldTotalCount;
    final p0 = s.points;
    s.markRevealed(old.drawId); // stale
    expect(s.activeDraw!.status, DrawStatus.committed);
    s.markRevealed(fresh.drawId); // 정상
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
    s.markRevealed(c.drawId);
    expect(before.status, DrawStatus.committed); // 옛 참조 그대로
    expect(s.activeDraw!.status, DrawStatus.revealed); // 새 객체
    expect(identical(before, s.activeDraw), isFalse);
  });
}
