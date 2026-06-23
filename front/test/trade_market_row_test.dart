import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/theme/app_colors.dart';
import 'package:front/features/trade/trade_list_screen.dart';

/// 거래 탭 시장 리스트 "가격·변동" 라인 회귀 검증 (2단계 레이아웃).
/// 정책: ①넓으면 가격+변동값 한 줄 ②좁으면 가격 1줄 + 변동액·퍼센트를 **한 묶음**으로 2줄.
/// 퍼센트만 단독 줄바꿈 금지(변동값은 한 Text). 숫자 ellipsis·전체 FittedBox 축소 없음.
/// 라벨 '한국판 예상가'는 여유 시 풀→'예상가' 축약→숨김. 하트와 최소 간격 고정.
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

  // 같은 줄(수직 overlap) 여부.
  bool sameLine(WidgetTester t, Finder a, Finder b) {
    final ra = t.getRect(a);
    final rb = t.getRect(b);
    return ra.top < rb.bottom && rb.top < ra.bottom;
  }

  // 변동값은 항상 한 묶음(amount+pct 한 Text) — 퍼센트 단독 분리 금지의 핵심 검증.
  final changeFinder = find.textContaining('-15,100원 (-36.6%)');

  for (final d in devices) {
    final name = d[0] as String;
    final size = d[1] as Size;
    for (final scale in scales) {
      testWidgets('시장행 — $name @ x$scale (overflow 0·변동값 한 묶음·잘림 0)', (tester) async {
        await pumpMeta(tester, stressMeta(), size, scale);
        expect(tester.takeException(), isNull, reason: '$name x$scale overflow');
        expect(find.textContaining('185,600'), findsOneWidget);
        // ★변동액·퍼센트가 한 Text(분리/단독 줄바꿈 없음).
        expect(changeFinder, findsOneWidget, reason: '$name x$scale 변동값 한 묶음');
      });
    }
  }

  testWidgets('넓은 폭 → 한 줄(가격·변동 같은 줄)', (tester) async {
    await pumpMeta(tester, stressMeta(), const Size(430, 932), 1.0, width: 600);
    expect(tester.takeException(), isNull);
    expect(sameLine(tester, find.textContaining('185,600'), changeFinder), isTrue,
        reason: '넓으면 한 줄');
    expect(find.text('한국판 예상가'), findsOneWidget); // 충분히 넓으면 풀 라벨
  });

  testWidgets('좁은 폭 → 2줄(변동값이 가격 아래, 한 묶음 유지)', (tester) async {
    await pumpMeta(tester, stressMeta(), const Size(320, 568), 1.0);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('185,600'), findsOneWidget);
    expect(changeFinder, findsOneWidget); // 여전히 한 묶음
    expect(sameLine(tester, find.textContaining('185,600'), changeFinder), isFalse,
        reason: '좁으면 변동값이 둘째 줄(퍼센트 단독 아님·한 묶음 통째)');
  });

  testWidgets('축약 rung 존재 — 폭 줄이면 "예상가" 축약 단계 존재(풀 드롭)', (tester) async {
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
    expect(shortRungSeen, isTrue, reason: '풀→축약(예상가) 단계 존재');
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
