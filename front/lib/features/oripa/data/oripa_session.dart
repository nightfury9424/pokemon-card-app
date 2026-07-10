import 'package:flutter/foundation.dart';
import 'oripa_mock.dart';
import 'oripa_prizes.dart';
import 'reveal_models.dart';

/// 한 번 뽑기 결과 — 확인시트 [1구 뽑기] 시점에 확정(애니 전). (화면 전달용 경량 값)
class DrawResult {
  final int number;
  final OripaPrize prize;
  const DrawResult(this.number, this.prize);
}

/// 진행 중 뽑기 상태 (spec §11·§B-6.3) — 재진입 복구·중복 방지의 단일 진실원.
enum DrawStatus { committed, revealed, resolved }

enum DrawResolution { keep, exchange }

class ActiveDraw {
  final String drawId;
  final String oripaId;
  final int number;
  final OripaPrize prize;
  final RevealDescriptor revealDescriptor;
  DrawStatus status;
  DrawResolution? resolution;
  ActiveDraw({
    required this.drawId,
    required this.oripaId,
    required this.number,
    required this.prize,
    required this.revealDescriptor,
    this.status = DrawStatus.committed,
    this.resolution,
  });
}

/// STEP 2 in-memory 세션 mock 상태 (ChangeNotifier 싱글톤, AuthState 패턴).
/// 앱 재시작 = 새 인스턴스 = 초기값 리셋. 영속/API/DB/원장 0.
class OripaSession extends ChangeNotifier {
  OripaSession._();
  static final OripaSession instance = OripaSession._();

  int _points = OripaMock.pointBalance;
  final List<HeldItem> _held = [...OripaMock.heldItems];
  final Map<String, Set<int>> _taken = {};
  final Map<String, int> _cursor = {};
  int _drawSeq = 0;
  ActiveDraw? _active;

  int get points => _points;
  List<HeldItem> get held => List.unmodifiable(_held);
  int get heldTotalCount => _held.length;
  ActiveDraw? get activeDraw => _active;

  Set<int> _takenOf(OripaProduct o) => _taken.putIfAbsent(
      o.oripaId,
      () => OripaDraw.initialTaken(o.oripaId, o.totalSlots, o.soldSlots));

  bool isTaken(OripaProduct o, int n) => _takenOf(o).contains(n);
  int remaining(OripaProduct o) => o.totalSlots - _takenOf(o).length;
  bool canDraw(OripaProduct o) => _points >= o.pricePerDraw && remaining(o) > 0;

  List<HeldItem> heldByShop(String shopId) =>
      _held.where((h) => h.shopId == shopId).toList();

  /// 매장별 남은 상품 있는 매장 (홈 보관함 요약).
  List<OripaShop> get shopsWithHeld =>
      OripaMock.shops.where((s) => heldByShop(s.shopId).isNotEmpty).toList();

  /// 확인시트 [1구 뽑기] 시점: 포인트 차감 + 다음 미획득 번호 확정(taken) + 반환.
  /// 결정론 — 애니메이션 도중 결과 결정 없음.
  /// 확인시트 [1구 뽑기]: 이중 커밋 방지 → 포인트 차감 + 번호 확정(taken) + drawCursor 이동
  /// + prize·RevealDescriptor 확정 + activeDraw(COMMITTED) 생성. 결정론(애니 중 결정 없음).
  /// 이전 draw가 RESOLVED면 새 draw로 원자 교체(다시 뽑기).
  /// 확인시트 [1구 뽑기]: **사전조건 통과 시에만** 원자적 상태 변경. 실패 시 무변경 + `null`.
  /// - #1 전역 active draw 1개: 진행 중(committed/revealed) draw 있으면 새 draw 차단
  ///   (같은 오리파=기존 결과 반환[이중탭 멱등], 다른 오리파=null[거절]).
  /// - #3 포인트 부족 / 매진(유효 번호 없음) → points·taken·cursor·activeDraw **전부 무변경**, null.
  DrawResult? confirmDraw(OripaProduct o) {
    // #1 전역 차단 (oripaId 무관).
    final cur = _active;
    if (cur != null && cur.status != DrawStatus.resolved) {
      return cur.oripaId == o.oripaId ? DrawResult(cur.number, cur.prize) : null;
    }
    // #3 포인트 부족 → 무변경.
    if (_points < o.pricePerDraw) return null;
    // 다음 유효 번호 계산 (아직 cursor/taken 미변경).
    final taken = _takenOf(o);
    final order = OripaDraw.orderOf(o.oripaId);
    var i = _cursor[o.oripaId] ?? 0;
    int number = 0;
    while (i < order.length) {
      final n = order[i];
      i++;
      if (!taken.contains(n)) {
        number = n;
        break;
      }
    }
    if (number <= 0) return null; // 매진/유효 번호 없음 → 무변경.
    // ── 여기부터 확정: 원자적 상태 변경 ──
    _points -= o.pricePerDraw;
    _cursor[o.oripaId] = i;
    taken.add(number);
    final prize = OripaDraw.prizeForNumber(o.oripaId, number);
    _drawSeq++;
    _active = ActiveDraw(
      drawId: 'draw_$_drawSeq',
      oripaId: o.oripaId,
      number: number,
      prize: prize,
      revealDescriptor: buildRevealDescriptor(prize, number: number),
    );
    notifyListeners();
    return DrawResult(number, prize);
  }

  /// hero 공개 완료 → REVEALED 전이 (COMMITTED에서만).
  void markRevealed() {
    final a = _active;
    if (a != null && a.status == DrawStatus.committed) {
      a.status = DrawStatus.revealed;
      notifyListeners();
    }
  }

  /// 보관하기 — 매장별 보관함에 +1. activeDraw를 RESOLVED(keep)로. **1회 래치**(연타 무시).
  void keepPrize(String shopId) {
    final a = _active;
    if (a == null || a.status != DrawStatus.revealed) return; // REVEALED에서만(+1회 래치)
    _held.add(HeldItem(
      itemId: '${a.drawId}_${_held.length}',
      shopId: shopId,
      name: a.prize.displayName,
      rarity: '', // 오리파 상품은 rarity 없음(카드 도메인 아님). HeldItem 호환 위해 빈값.
      exchangePoints: a.prize.exchangePoints,
    ));
    a.status = DrawStatus.resolved;
    a.resolution = DrawResolution.keep;
    notifyListeners();
  }

  /// 포인트 교환 — 세션 포인트에 exchangePoints 추가. RESOLVED(exchange)로. **1회 래치**.
  void exchangePrize() {
    final a = _active;
    if (a == null || a.status != DrawStatus.revealed) return; // REVEALED에서만(+1회 래치)
    _points += a.prize.exchangePoints;
    a.status = DrawStatus.resolved;
    a.resolution = DrawResolution.exchange;
    notifyListeners();
  }

  /// [오리파로 돌아가기] — RESOLVED activeDraw만 clear(진행 중이면 유지).
  void clearActiveDraw() {
    if (_active != null && _active!.status == DrawStatus.resolved) {
      _active = null;
      notifyListeners();
    }
  }

  /// 앱 재시작 대체용(테스트) — 초기값 리셋.
  void reset() {
    _points = OripaMock.pointBalance;
    _held
      ..clear()
      ..addAll(OripaMock.heldItems);
    _taken.clear();
    _cursor.clear();
    _active = null;
    _drawSeq = 0;
    notifyListeners();
  }
}
