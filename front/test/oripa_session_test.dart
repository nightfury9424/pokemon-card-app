import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';

/// Stage 2: activeDraw 수명주기 / 중복 방지 / 래치 / 사전조건 (spec §11·§B-6).
void main() {
  final s = OripaSession.instance;
  final o1 = OripaMock.oripaById('o1'); // pricePerDraw 50000, 선두 47→9→52
  final o3 = OripaMock.oripaById('o3'); // 다른 오리파(다른 매장)

  setUp(() => s.reset());

  // 정상 draw→reveal→resolve 헬퍼
  DrawResult drawReveal(OripaProduct o) {
    final r = s.confirmDraw(o)!;
    s.markRevealed();
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
    expect(a.oripaId, 'o1');
    expect(a.revealDescriptor.openingHeader, '47번 당첨');
  });

  test('2) commit 연타(같은 오리파) → 두 번째 무시 (포인트 1회만, 동일 activeDraw)', () {
    final p0 = s.points;
    final r1 = s.confirmDraw(o1)!;
    final id1 = s.activeDraw!.drawId;
    final r2 = s.confirmDraw(o1)!; // 진행 중 → 기존 반환
    expect(s.points, p0 - o1.pricePerDraw); // 1회만 차감
    expect(r2.number, r1.number);
    expect(s.activeDraw!.drawId, id1); // 새 draw 안 생김
  });

  test('3) COMMITTED/REVEALED 중 같은 오리파 새 draw 금지', () {
    s.confirmDraw(o1);
    final id = s.activeDraw!.drawId;
    s.markRevealed();
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.confirmDraw(o1); // revealed=진행중 → 무시
    expect(s.activeDraw!.drawId, id);
  });

  test('4) hero 완료 → REVEALED 전이 (committed에서만, 멱등)', () {
    s.confirmDraw(o1);
    expect(s.activeDraw!.status, DrawStatus.committed);
    s.markRevealed();
    expect(s.activeDraw!.status, DrawStatus.revealed);
    s.markRevealed();
    expect(s.activeDraw!.status, DrawStatus.revealed);
  });

  test('5) KEEP 또는 EXCHANGE 하나만 1회 → RESOLVED (다른 쪽 무시)', () {
    s.confirmDraw(o1);
    final held0 = s.heldTotalCount;
    s.markRevealed();
    s.keepPrize('s1');
    expect(s.activeDraw!.status, DrawStatus.resolved);
    expect(s.activeDraw!.resolution, DrawResolution.keep);
    expect(s.heldTotalCount, held0 + 1);
    final pts = s.points;
    s.exchangePrize(); // resolved → 무시
    expect(s.points, pts);
  });

  test('6) resolution 연타 → held/points 중복 반영 금지', () {
    drawReveal(o1);
    final h0 = s.heldTotalCount;
    s.keepPrize('s1');
    s.keepPrize('s1');
    s.keepPrize('s1');
    expect(s.heldTotalCount, h0 + 1);
    s.reset();
    drawReveal(o1);
    final ex = s.activeDraw!.prize.exchangePoints;
    final p0 = s.points;
    s.exchangePrize();
    s.exchangePrize();
    expect(s.points, p0 + ex); // 1회만
  });

  test('7) 돌아가기 → RESOLVED activeDraw clear (진행 중이면 유지)', () {
    s.confirmDraw(o1);
    s.clearActiveDraw(); // COMMITTED → 유지
    expect(s.activeDraw, isNotNull);
    s.markRevealed();
    s.keepPrize('s1'); // RESOLVED
    s.clearActiveDraw();
    expect(s.activeDraw, isNull);
  });

  test('8) 다시 뽑기 → 이전 RESOLVED를 새 COMMITTED로 원자 교체', () {
    final r1 = drawReveal(o1);
    final id1 = s.activeDraw!.drawId;
    s.keepPrize('s1'); // resolved
    final r2 = s.confirmDraw(o1)!; // 다시 뽑기
    expect(s.activeDraw!.drawId, isNot(id1));
    expect(s.activeDraw!.status, DrawStatus.committed);
    expect(r1.number, 47);
    expect(r2.number, 9); // 다음 미획득 번호
  });

  test('9) reset(프로세스 리셋 대체) → activeDraw·points 초기화', () {
    s.confirmDraw(o1);
    expect(s.activeDraw, isNotNull);
    s.reset();
    expect(s.activeDraw, isNull);
    expect(s.points, OripaMock.pointBalance);
  });

  // ── Stage2 보정: 계약 구멍 3종 ──

  test('10) 다른 오리파(oripaId)의 진행 중 draw도 새 commit 전역 차단 → null·무변경', () {
    s.confirmDraw(o1); // o1 진행 중
    final p0 = s.points;
    final actId = s.activeDraw!.drawId;
    final r = s.confirmDraw(o3); // 다른 매장 → 전역 차단
    expect(r, isNull);
    expect(s.points, p0); // o3 차감 없음
    expect(s.activeDraw!.drawId, actId); // 여전히 o1 draw
    expect(s.isTaken(o3, s.activeDraw!.number), isFalse);
  });

  test('11) COMMITTED 상태에서 KEEP/EXCHANGE 차단(REVEALED에서만)', () {
    s.confirmDraw(o1); // COMMITTED (markRevealed 안 함)
    final h0 = s.heldTotalCount;
    final p0 = s.points;
    s.keepPrize('s1'); // 차단
    s.exchangePrize(); // 차단
    expect(s.heldTotalCount, h0);
    expect(s.points, p0);
    expect(s.activeDraw!.status, DrawStatus.committed); // 여전히 미해결
  });

  test('12) 포인트 부족 → null, points·activeDraw·remaining 무변경', () {
    // 2회 정상 소진 (125000 - 100000 = 25000 < 50000)
    drawReveal(o1);
    s.keepPrize('s1');
    drawReveal(o1);
    s.keepPrize('s1');
    expect(s.points, lessThan(o1.pricePerDraw));
    final pts = s.points;
    final rem = s.remaining(o1);
    final act = s.activeDraw;
    final r = s.confirmDraw(o1);
    expect(r, isNull);
    expect(s.points, pts);
    expect(s.remaining(o1), rem);
    expect(s.activeDraw, same(act)); // 변경 없음
  });

  test('13) 유효 번호 없음(빈 order) → null, 무변경', () {
    const empty = OripaProduct(
      oripaId: 'zz_empty', shopId: 's1', title: 't',
      pricePerDraw: 0, totalSlots: 1, remainingSlots: 1,
      type: OripaType.number, featuredPrizes: [],
    );
    final p0 = s.points;
    final r = s.confirmDraw(empty); // orderOf('zz_empty')=[] → number 0
    expect(r, isNull);
    expect(s.points, p0); // pricePerDraw 0이지만 애초에 미변경
    expect(s.activeDraw, isNull);
  });

  test('14) 실패(전역 차단) 후 cursor·taken·activeDraw 동일', () {
    final r1 = s.confirmDraw(o1)!;
    final takenBefore = {...(s.activeDraw != null ? {r1.number} : <int>{})};
    final actId = s.activeDraw!.drawId;
    // 진행 중 상태에서 실패 시도들
    s.confirmDraw(o3); // 전역 차단
    s.confirmDraw(o1); // 같은 오리파 이중탭(기존 반환, 새 taken 없음)
    expect(s.activeDraw!.drawId, actId); // 동일 draw
    expect(s.isTaken(o1, r1.number), isTrue);
    // r1 외 새로운 번호가 taken되지 않았는지 (9는 아직 미획득)
    expect(s.isTaken(o1, 9), isFalse);
    expect(takenBefore.contains(r1.number), isTrue);
  });
}
