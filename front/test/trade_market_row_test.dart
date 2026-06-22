import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/theme/app_colors.dart';
import 'package:front/features/trade/trade_list_screen.dart';

/// 거래 탭 시장 리스트 행의 "가격·변동" 라인 회귀 검증.
/// 기존 버그: price + 발매판라벨 + 변동(-15,100원 (-36.6%))을 고정 Row 로 한 줄에
/// 우겨넣어 좁은 폭에서 오른쪽 overflow → 변동 정보 잘림 + 우측 하트와 겹침.
/// 수정: MarketRowPriceMeta(Wrap) — 변동액/퍼센트가 다음 줄로 내려가고 잘리지 않음.
///
/// 실제 행에서 이 위젯은 [순위22 + 8 + 이미지44 + 14 + Expanded + 하트~34 + 좌우패딩40]
/// 중 Expanded 영역에 들어간다 → 가용폭 ≈ 화면폭 - 162 로 제약해 검증.
void main() {
  final devices = <List<dynamic>>[
    ['320x568', const Size(320, 568)],
    ['375x667', const Size(375, 667)],
    ['375x812', const Size(375, 812)],
    ['390x844', const Size(390, 844)],
    ['430x932', const Size(430, 932)],
  ];
  final scales = <double>[1.0, 1.3, 1.6];

  // 행 내부 고정 영역(순위/이미지/하트/좌우 패딩) 합산 ≈ 162.
  const fixedChrome = 162.0;

  Future<void> pumpMeta(
    WidgetTester tester,
    Widget meta,
    Size size,
    double scale,
  ) async {
    tester.view.devicePixelRatio = 3.0;
    tester.view.physicalSize = size * 3.0;
    addTearDown(tester.view.reset);
    final expandedWidth = size.width - fixedChrome;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: TextScaler.linear(scale)),
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

  // 스트레스: 큰 음수 변동액 + 긴 퍼센트.
  MarketRowPriceMeta stressMeta() => const MarketRowPriceMeta(
        price: 185600,
        priceLabelText: '한국판 예상가',
        changeAmount: '-15,100원',
        changePct: '(-36.6%)',
        changeColor: AppColors.blue,
      );

  for (final d in devices) {
    final name = d[0] as String;
    final size = d[1] as Size;
    for (final scale in scales) {
      testWidgets('시장행 가격·변동 — $name @ x$scale (overflow 0, 잘림 0)',
          (tester) async {
        await pumpMeta(tester, stressMeta(), size, scale);
        expect(tester.takeException(), isNull,
            reason: '$name x$scale 가격·변동 라인 overflow');
        // 변동액·퍼센트 전체 노출(ellipsis 잘림 없음).
        expect(find.textContaining('-15,100원'), findsOneWidget,
            reason: '$name x$scale 변동액 노출');
        expect(find.textContaining('-36.6%'), findsOneWidget,
            reason: '$name x$scale 퍼센트 노출');
      });
    }
  }

  testWidgets('등락 숨김(저가 정책) — 변동 칩 없이 가격+라벨만', (tester) async {
    await pumpMeta(
      tester,
      const MarketRowPriceMeta(
        price: 3000,
        priceLabelText: '한국판 예상가',
        changeAmount: null,
        changePct: null,
        changeColor: AppColors.textMuted,
      ),
      const Size(320, 568),
      1.6,
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
        priceLabelText: '시세 준비중',
        changeAmount: null,
        changePct: null,
        changeColor: AppColors.textMuted,
      ),
      const Size(375, 667),
      1.0,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('시세 없음'), findsOneWidget);
  });

  testWidgets('좁은 폭 큰 글자 → 변동이 다음 줄로(잘림 아님)', (tester) async {
    // 320 폭 x1.6: 가격+라벨이 1줄을 채우면 변동액/퍼센트는 아래 줄로 내려가야 한다.
    await pumpMeta(tester, stressMeta(), const Size(320, 568), 1.6);
    expect(tester.takeException(), isNull);
    final priceY = tester.getTopLeft(find.textContaining('185,600')).dy;
    final amountY = tester.getTopLeft(find.textContaining('-15,100원')).dy;
    expect(amountY, greaterThan(priceY),
        reason: '좁고 큰 글자: 변동액이 가격보다 아래 줄(Wrap 전환, 잘림 아님)');
  });
}
