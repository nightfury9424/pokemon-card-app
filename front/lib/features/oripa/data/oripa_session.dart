import 'package:flutter/foundation.dart';
import 'oripa_mock.dart';
import 'oripa_prizes.dart';

/// 한 번 뽑기 결과 — 확인시트 [1구 뽑기] 시점에 확정(애니 전).
class DrawResult {
  final int number;
  final OripaPrize prize;
  const DrawResult(this.number, this.prize);
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

  int get points => _points;
  List<HeldItem> get held => List.unmodifiable(_held);
  int get heldTotalCount => _held.length;

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
  DrawResult confirmDraw(OripaProduct o) {
    _points -= o.pricePerDraw;
    final taken = _takenOf(o);
    final order = OripaDraw.orderOf(o.oripaId);
    var i = _cursor[o.oripaId] ?? 0;
    int number = -1;
    while (i < order.length) {
      final n = order[i];
      i++;
      if (!taken.contains(n)) {
        number = n;
        break;
      }
    }
    _cursor[o.oripaId] = i;
    if (number > 0) taken.add(number);
    notifyListeners();
    return DrawResult(number, OripaDraw.prizeForNumber(o.oripaId, number));
  }

  /// 보관하기 — 매장별 보관함에 +1.
  void keepPrize(String shopId, DrawResult r) {
    _held.add(HeldItem(
      itemId: 'draw_${r.number}_${_held.length}',
      shopId: shopId,
      name: r.prize.displayName,
      rarity: '', // 오리파 상품은 rarity 없음(카드 도메인 아님). HeldItem 호환 위해 빈값.
      exchangePoints: r.prize.exchangePoints,
    ));
    notifyListeners();
  }

  /// 포인트 교환 — 세션 포인트에 exchangePoints 추가.
  void exchangePrize(DrawResult r) {
    _points += r.prize.exchangePoints;
    notifyListeners();
  }

  /// 앱 재시작 대체용(테스트) — 초기값 리셋.
  void reset() {
    _points = OripaMock.pointBalance;
    _held
      ..clear()
      ..addAll(OripaMock.heldItems);
    _taken.clear();
    _cursor.clear();
    notifyListeners();
  }
}
