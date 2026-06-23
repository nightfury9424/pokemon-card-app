import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/theme/app_colors.dart';
import 'package:front/features/trade/trade_list_screen.dart';

/// 거래 탭 시장 리스트 "가격·변동" 라인 회귀 검증.
/// 정책: **한 줄 유지** + 가격·변동값 숫자는 절대 ellipsis 로 자르지 않음.
/// 좁은 폭 적응 우선순위 = ①`한국판 예상가` 라벨 풀→축약(`예상가`)→숨김 ②변동값만 floor 축소
/// ③극단 폭은 FittedBox 균등 축소(정보 보존). 변동값(-15,100원 (-36.6%))은 한 묶음으로 유지.
///
/// 실제 행에서 이 위젯은 Expanded 영역(가용폭 ≈ 화면폭 - 162[순위/이미지/하트/패딩])에 들어간다.
void main() {
  final devices = <List<dynamic>>[
    ['320x568', const Size(320, 568)],
    ['375x667', const Size(375, 667)],
    ['375x812', const Size(375, 812)],
    ['390x844', const Size(390, 844)],
    ['430x932', const Size(430, 932)],
  ];
  final scales = <double>[1.0, 1.3, 1.6];
  const fixedChrome = 162.0;

  Future<void> pumpMeta(WidgetTester tester, Widget meta, Size size, double scale,
      {double? width}) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = size * 3.0;
    addTearDown(tester.view.reset);
    final expandedWidth = width ?? (size.width - fixedChrome);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: expandedWidth, child: meta),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  MarketRowPriceMeta stressMeta() => const MarketRowPriceMeta(
        price: 185600,
        priceLabelText: '한국판 예상가',
        changeAmount: '-15,100원',
        changePct: '(-36.6%)',
        changeColor: AppColors.blue,
      );

  // 두 위젯이 같은 줄(수직 overlap) 인가 — 폰트 크기/정렬 무관하게 견고.
  bool sameLine(WidgetTester t, Finder a, Finder b) {
    final ra = t.getRect(a);
    final rb = t.getRect(b);
    return ra.top < rb.bottom && rb.top < ra.bottom;
  }

  for (final d in devices) {
    final name = d[0] as String;
    final size = d[1] as Size;
    for (final scale in scales) {
      testWidgets('시장행 가격·변동 — $name @ x$scale (한 줄·overflow 0·잘림 0)',
          (tester) async {
        await pumpMeta(tester, stressMeta(), size, scale);
        expect(tester.takeException(), isNull, reason: '$name x$scale overflow');
        // 가격·변동 숫자 전체 노출(ellipsis 잘림 없음).
        expect(find.textContaining('185,600'), findsOneWidget);
        expect(find.textContaining('-15,100원'), findsOneWidget);
        expect(find.textContaining('-36.6%'), findsOneWidget);
        // ★한 줄 유지: 가격과 변동값이 같은 줄.
        expect(sameLine(tester, find.textContaining('185,600'), find.textContaining('-15,100원')),
            isTrue, reason: '$name x$scale 가격·변동 같은 줄(2줄 분리 금지)');
      });
    }
  }

  testWidgets('충분히 넓으면 → 풀 라벨 "한국판 예상가" 표시(한 줄)', (tester) async {
    await pumpMeta(tester, stressMeta(), const Size(430, 932), 1.0, width: 600);
    expect(tester.takeException(), isNull);
    expect(find.text('한국판 예상가'), findsOneWidget);
    expect(sameLine(tester, find.textContaining('185,600'), find.textContaining('-36.6%')), isTrue);
  });

  testWidgets('축약 rung 존재 — 폭을 줄이면 어떤 중간 폭에서 "예상가"만 노출(풀 드롭)', (tester) async {
    // 글자 메트릭 의존 없이 폭 스윕으로 "풀 드롭 + 축약 노출" 단계가 존재함을 검증.
    const meta = MarketRowPriceMeta(
      price: 100, priceLabelText: '한국판 예상가',
      changeAmount: null, changePct: null, changeColor: AppColors.textMuted,
    );
    bool shortRungSeen = false;
    for (double w = 60; w <= 220 && !shortRungSeen; w += 4) {
      await pumpMeta(tester, meta, const Size(390, 844), 1.0, width: w);
      final shortShown = find.text('예상가').evaluate().isNotEmpty;
      final fullShown = find.text('한국판 예상가').evaluate().isNotEmpty;
      if (shortShown && !fullShown) shortRungSeen = true;
    }
    expect(shortRungSeen, isTrue, reason: '폭 축소 시 풀→축약(예상가) 단계가 존재해야');
  });

  testWidgets('좁은 폭 → 풀 라벨 숨김(축약/드롭), 변동값은 끝까지·한 줄', (tester) async {
    await pumpMeta(tester, stressMeta(), const Size(320, 568), 1.0);
    expect(tester.takeException(), isNull);
    expect(find.text('한국판 예상가'), findsNothing); // 풀 라벨 드롭(축약 or 숨김)
    expect(find.textContaining('-15,100원'), findsOneWidget); // 변동값 보존
    expect(find.textContaining('-36.6%'), findsOneWidget);
    expect(sameLine(tester, find.textContaining('185,600'), find.textContaining('-15,100원')),
        isTrue, reason: '좁아도 한 줄 유지');
  });

  testWidgets('등락 숨김(저가 정책) — 변동 칩 없이 가격+라벨만', (tester) async {
    await pumpMeta(
      tester,
      const MarketRowPriceMeta(
        price: 3000, priceLabelText: '한국판 예상가',
        changeAmount: null, changePct: null, changeColor: AppColors.textMuted,
      ),
      const Size(320, 568), 1.6,
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('3,000'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('시세 없음 — 가격 자리에 시세 없음', (tester) async {
    await pumpMeta(
      tester,
      const MarketRowPriceMeta(
        price: null, priceLabelText: '시세 준비중',
        changeAmount: null, changePct: null, changeColor: AppColors.textMuted,
      ),
      const Size(375, 667), 1.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('시세 없음'), findsOneWidget);
  });
}
