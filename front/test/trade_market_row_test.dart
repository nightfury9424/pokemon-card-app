import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/theme/app_colors.dart';
import 'package:front/features/trade/trade_list_screen.dart';

/// 거래 탭 시장 리스트 "가격·변동" 라인 회귀 검증 (2단계 레이아웃).
/// 정책: ①넓으면 가격+변동값 한 줄 ②좁으면 가격 1줄 + 변동액·퍼센트를 **한 묶음**으로 2줄.
/// 퍼센트만 단독 줄바꿈 금지(변동값은 한 Text). 숫자 ellipsis·전체 FittedBox 축소 없음.
/// ★행별 '예상가' 라벨은 제거됨(목록 일관성, 맥락은 탭 아래 안내 문구). 하트와 최소 간격 고정.
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
        // ★변동값이 실제로 "한 줄" 렌더(2줄로 wrap되면 높이가 ~2배 → 검출). 가격도 한 줄.
        final changeH = tester.getSize(changeFinder).height;
        final priceH = tester.getSize(find.textContaining('185,600')).height;
        expect(changeH, lessThanOrEqualTo(priceH * 1.5),
            reason: '$name x$scale 변동값 한 줄(퍼센트 단독 줄바꿈/3줄 금지)');
      });
    }
  }

  // 주: "기본 글자크기서 축소 없음"은 위젯테스트로 검증 불가 — 테스트 폰트('FlutterTest')가
  //     고정폭(글자당 fontSize)이라 한글/숫자 폭이 실폰트와 크게 달라 base scale에도 FittedBox가
  //     오작동함(테스트 아티팩트, 실버그 아님). 해당 시각 게이트는 시뮬레이터 실폰트 캡처로만 확인 가능.

  testWidgets('넓은 폭 → 한 줄(가격·변동 같은 줄)', (tester) async {
    await pumpMeta(tester, stressMeta(), const Size(430, 932), 1.0, width: 600);
    expect(tester.takeException(), isNull);
    expect(sameLine(tester, find.textContaining('185,600'), changeFinder), isTrue,
        reason: '넓으면 한 줄');
    expect(find.textContaining('예상가'), findsNothing); // ★행 안에 라벨 없음
  });

  testWidgets('좁은 폭 → 2줄(변동값이 가격 아래, 한 묶음 유지)', (tester) async {
    await pumpMeta(tester, stressMeta(), const Size(320, 568), 1.0);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('185,600'), findsOneWidget);
    expect(changeFinder, findsOneWidget); // 여전히 한 묶음
    expect(sameLine(tester, find.textContaining('185,600'), changeFinder), isFalse,
        reason: '좁으면 변동값이 둘째 줄(퍼센트 단독 아님·한 묶음 통째)');
  });

  testWidgets('행 안에 예상가/참고가 라벨 없음(폭 무관)', (tester) async {
    for (double w = 80; w <= 320; w += 20) {
      await pumpMeta(tester, stressMeta(), const Size(390, 844), 1.0, width: w);
      expect(tester.takeException(), isNull, reason: 'w=$w overflow');
      expect(find.textContaining('예상가'), findsNothing, reason: 'w=$w 행 라벨 없음');
      expect(find.textContaining('참고가'), findsNothing, reason: 'w=$w 행 라벨 없음');
    }
  });

  testWidgets('등락 숨김(저가 정책) — 변동 칩 없이 가격만', (tester) async {
    await pumpMeta(
      tester,
      const MarketRowPriceMeta(
        price: 3000,
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
        price: null,
        changeAmount: null, changePct: null, changeColor: AppColors.textMuted,
      ),
      const Size(375, 667), 1.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('시세 없음'), findsOneWidget);
  });
}
