import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';

/// Stage 2: activeDraw 수명주기 / 중복 방지 / 래치 / 사전조건 / drawId-scoped (spec §11·§B-6).
void main() {
  final s = OripaSession.instance;
  final o1 = OripaMock.oripaById('o1'); // pricePerDraw 50000, 선두 47→9→52
  final o3 = OripaMock.oripaById('o3'); // 다른 오리파(다른 매장)

  setUp(() => s.reset());

  String id() => s.activeDraw!.drawId;

  // 정상 draw→reveal 헬퍼 (drawId 스코프)
  DrawResult drawReveal(OripaProduct o) {
    final r = s.confirmDraw(o)!;
    s.markRevealed(id());
    return r;
  }

  test('1) commit 1회 → points 차감·taken·activeDraw(COMMITTED) 정확히 1회', () {
    final p0 = s.points;
    final r = s.confirmDraw(o1)!;
    expect(r.number, 47);
    expect(s.points, p0 - o1.pricePerDraw);
    expect(s.isTaken(o1, 47), isTrue);
    final a = s.activeDraw!;
    expect(a.status, DrawStatus.committed);
    expect(a.number, 47);
    expect(a.revealDescriptor.openingHeader, '47번 당첨');
  });

  test('2) commit 연타(같은 오리파) → 두 번째 무시 (포인트 1회만)', () {
    final p0 = s.points;
    final r1 = s.confirmDraw(o1)!;
    final id1 = id();
    final r2 = s.confirmDraw(o1)!;
    expect(s.points, p0 - o1.pricePerDraw);
    expect(r2.number, r1.number);
    expect(id(), id1);
  });

  test('3) COMMITTED/REVEALED 중 같은 오리파 새 draw 금지', () {
    s.confirmDraw(o1);
    final id1 = id();
    s.markRevealed(id1);
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.confirmDraw(o1);
    expect(id(), id1);
  });

  test('4) hero 완료 → REVEALED 전이 (committed에서만, 멱등)', () {
    s.confirmDraw(o1);
    expect(s.activeDraw!.status, DrawStatus.committed);
    s.markRevealed(id());
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.markRevealed(id());
    expect(s.activeDraw!.status, DrawStatus.revealed);
  });

  test('5) KEEP 또는 EXCHANGE 하나만 1회 → RESOLVED (다른 쪽 무시)', () {
    s.confirmDraw(o1);
    final held0 = s.heldTotalCount;
    final drawId = id();
    s.markRevealed(drawId);
    s.keepPrize(drawId, 's1');
    expect(s.activeDraw!.status, DrawStatus.resolved);
    expect(s.activeDraw!.resolution, DrawResolution.keep);
    expect(s.heldTotalCount, held0 + 1);
    final pts = s.points;
    s.exchangePrize(drawId);
    expect(s.points, pts);
  });

  test('6) resolution 연타 → held/points 중복 반영 금지', () {
    drawReveal(o1);
    final h0 = s.heldTotalCount;
    final d1 = id();
    s.keepPrize(d1, 's1');
    s.keepPrize(d1, 's1');
    s.keepPrize(d1, 's1');
    expect(s.heldTotalCount, h0 + 1);
    s.reset();
    drawReveal(o1);
    final ex = s.activeDraw!.prize.exchangePoints;
    final p0 = s.points;
    final d2 = id();
    s.exchangePrize(d2);
    s.exchangePrize(d2);
    expect(s.points, p0 + ex);
  });

  test('7) 돌아가기 → RESOLVED activeDraw clear (진행 중이면 유지)', () {
    s.confirmDraw(o1);
    final drawId = id();
    s.clearActiveDraw(drawId); // COMMITTED → 유지
    expect(s.activeDraw, isNotNull);
    s.markRevealed(drawId);
    s.keepPrize(drawId, 's1'); // RESOLVED
    s.clearActiveDraw(drawId);
    expect(s.activeDraw, isNull);
  });

  test('8) 다시 뽑기 → 이전 RESOLVED를 새 COMMITTED로 원자 교체', () {
    final r1 = drawReveal(o1);
    final id1 = id();
    s.keepPrize(id1, 's1');
    final r2 = s.confirmDraw(o1)!;
    expect(id(), isNot(id1));
    expect(s.activeDraw!.status, DrawStatus.committed);
    expect(r1.number, 47);
    expect(r2.number, 9);
  });

  test('9) reset → activeDraw·points 초기화', () {
    s.confirmDraw(o1);
    expect(s.activeDraw, isNotNull);
    s.reset();
    expect(s.activeDraw, isNull);
    expect(s.points, OripaMock.pointBalance);
  });

  test('10) 다른 오리파 진행 중 draw도 전역 차단 → null·무변경', () {
    s.confirmDraw(o1);
    final p0 = s.points;
    final id1 = id();
    final r = s.confirmDraw(o3);
    expect(r, isNull);
    expect(s.points, p0);
    expect(id(), id1);
    expect(s.isTaken(o3, s.activeDraw!.number), isFalse);
  });

  test('11) COMMITTED에서 KEEP/EXCHANGE 차단(REVEALED에서만)', () {
    s.confirmDraw(o1);
    final drawId = id();
    final h0 = s.heldTotalCount;
    final p0 = s.points;
    s.keepPrize(drawId, 's1');
    s.exchangePrize(drawId);
    expect(s.heldTotalCount, h0);
    expect(s.points, p0);
    expect(s.activeDraw!.status, DrawStatus.committed);
  });

  test('12) 포인트 부족 → null, points·remaining·activeDraw 무변경', () {
    drawReveal(o1);
    s.keepPrize(id(), 's1');
    drawReveal(o1);
    s.keepPrize(id(), 's1');
    expect(s.points, lessThan(o1.pricePerDraw));
    final pts = s.points;
    final rem = s.remaining(o1);
    final act = s.activeDraw;
    final r = s.confirmDraw(o1);
    expect(r, isNull);
    expect(s.points, pts);
    expect(s.remaining(o1), rem);
    expect(s.activeDraw, same(act));
  });

  test('13) 유효 번호 없음(빈 order) → null, activeDraw 무변경', () {
    const empty = OripaProduct(
      oripaId: 'zz_empty', shopId: 's1', title: 't',
      pricePerDraw: 0, totalSlots: 1, remainingSlots: 1,
      type: OripaType.number, featuredPrizes: [],
    );
    final p0 = s.points;
    final r = s.confirmDraw(empty);
    expect(r, isNull);
    expect(s.points, p0);
    expect(s.activeDraw, isNull);
  });

  test('14) 전역 차단 실패 후 taken/activeDraw 동일', () {
    final r1 = s.confirmDraw(o1)!;
    final id1 = id();
    s.confirmDraw(o3); // 전역 차단
    s.confirmDraw(o1); // 이중탭(기존 반환)
    expect(id(), id1);
    expect(s.isTaken(o1, r1.number), isTrue);
    expect(s.isTaken(o1, 9), isFalse); // 새 taken 없음
  });

  test('15) 오래된 drawId 콜백은 새 draw를 오염하지 못함', () {
    s.confirmDraw(o1);
    final oldId = id();
    s.markRevealed(oldId);
    s.keepPrize(oldId, 's1'); // resolved
    s.clearActiveDraw(oldId); // active null
    // 새 draw
    s.confirmDraw(o1);
    final newId = id();
    expect(newId, isNot(oldId));
    final h0 = s.heldTotalCount;
    final p0 = s.points;
    // 오래된 id로 시도 → 전부 무시
    s.markRevealed(oldId);
    expect(s.activeDraw!.status, DrawStatus.committed);
    s.markRevealed(newId); // 정상
    s.keepPrize(oldId, 's1'); // stale
    s.exchangePrize(oldId); // stale
    expect(s.heldTotalCount, h0);
    expect(s.points, p0);
    expect(s.activeDraw!.status, DrawStatus.revealed); // resolve 안 됨
    // 올바른 id로는 동작
    s.keepPrize(newId, 's1');
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
    expect(r, isNull);
    expect(notifs, 0); // 상태 변경 알림 0
    expect(s.activeDraw, isNull);
  });
}
