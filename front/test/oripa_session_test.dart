import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';

/// Stage 2: activeDraw 수명주기 / 중복 방지 / 래치 (spec §11·§B-6).
void main() {
  final s = OripaSession.instance;
  final o1 = OripaMock.oripaById('o1'); // pricePerDraw 50000, 선두 47→9→52

  setUp(() => s.reset());

  test('1) commit 1회 → points 차감·taken·activeDraw(COMMITTED) 정확히 1회', () {
    final p0 = s.points;
    final r = s.confirmDraw(o1);
    expect(r.number, 47);
    expect(s.points, p0 - o1.pricePerDraw);
    expect(s.isTaken(o1, 47), isTrue);
    final a = s.activeDraw!;
    expect(a.status, DrawStatus.committed);
    expect(a.number, 47);
    expect(a.oripaId, 'o1');
    expect(a.revealDescriptor.openingHeader, '47번 당첨');
  });

  test('2) commit 연타 → 두 번째 무시 (포인트 1회만, 동일 activeDraw)', () {
    final p0 = s.points;
    final r1 = s.confirmDraw(o1);
    final id1 = s.activeDraw!.drawId;
    final r2 = s.confirmDraw(o1); // 진행 중 → 무시
    expect(s.points, p0 - o1.pricePerDraw); // 1회만 차감
    expect(r2.number, r1.number);
    expect(s.activeDraw!.drawId, id1); // 새 draw 안 생김
  });

  test('3) COMMITTED/REVEALED 중 새 draw 금지', () {
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
    s.markRevealed(); // 재호출 무해
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
    s.exchangePrize(); // 이미 resolved → 무시
    expect(s.points, pts);
  });

  test('6) resolution 연타 → held/points 중복 반영 금지', () {
    // keep 연타
    s.confirmDraw(o1);
    final h0 = s.heldTotalCount;
    s.keepPrize('s1');
    s.keepPrize('s1');
    s.keepPrize('s1');
    expect(s.heldTotalCount, h0 + 1);
    // exchange 연타 (새 draw)
    s.reset();
    s.confirmDraw(o1);
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
    s.keepPrize('s1'); // RESOLVED
    s.clearActiveDraw();
    expect(s.activeDraw, isNull);
  });

  test('8) 다시 뽑기 → 이전 RESOLVED를 새 COMMITTED로 원자 교체', () {
    final r1 = s.confirmDraw(o1);
    final id1 = s.activeDraw!.drawId;
    s.keepPrize('s1'); // resolved
    final r2 = s.confirmDraw(o1); // 다시 뽑기
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
}
