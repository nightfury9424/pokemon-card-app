import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';
import 'package:front/features/oripa/draw/oripa_draw_screen.dart';

/// 3b-2 통합: route drawId 검증 / 재진입 분기 / 결과 화면 내부 완결.
void main() {
  final s = OripaSession.instance;
  final o1 = OripaMock.oripaById('o1');

  Widget app() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('DETAIL'))),
        GoRoute(
          path: '/draw/:id',
          builder: (_, st) =>
              OripaDrawScreen(oripaId: 'o1', drawId: st.extra! as String),
        ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  Future<GoRouter> pumpTo(WidgetTester t, String drawId) async {
    final w = app();
    await t.pumpWidget(w);
    final router = (w as MaterialApp).routerConfig as GoRouter;
    router.push('/draw/o1', extra: drawId);
    await t.pumpAndSettle();
    return router;
  }

  setUp(() => s.reset());

  testWidgets('불일치 drawId(active 없음) → 애니 없이 안전 복귀', (t) async {
    await pumpTo(t, 'nonexistent');
    expect(find.text('DETAIL'), findsOneWidget); // 상세로 복귀
  });

  testWidgets('REVEALED 재진입 → HERO+결과 액션 즉시(보관/교환)', (t) async {
    final c = s.confirmDraw(o1) as DrawCreated;
    s.markRevealStarted(c.drawId);
    s.markRevealed(c.drawId); // REVEALED
    await pumpTo(t, c.drawId);
    expect(find.text('보관하기'), findsOneWidget); // 결과 액션 즉시 복구
  });

  testWidgets('RESOLVED 재진입 → clear 후 상세 복귀', (t) async {
    final c = s.confirmDraw(o1) as DrawCreated;
    s.markRevealStarted(c.drawId);
    s.markRevealed(c.drawId);
    s.keepPrize(c.drawId, o1.shopId); // RESOLVED
    await pumpTo(t, c.drawId);
    expect(find.text('DETAIL'), findsOneWidget); // 복귀
    expect(s.activeDraw, isNull); // clear됨
  });

  testWidgets('보관 → RESOLVED, 돌아가기 버튼으로 종료', (t) async {
    final c = s.confirmDraw(o1) as DrawCreated;
    s.markRevealStarted(c.drawId);
    s.markRevealed(c.drawId);
    await pumpTo(t, c.drawId);
    await t.tap(find.text('보관하기'));
    await t.pumpAndSettle();
    expect(find.text('오리파로 돌아가기'), findsOneWidget); // resolved 후 종료 버튼
    expect(s.activeDraw!.status, DrawStatus.resolved);
  });

  testWidgets('stale drawId 보관 → 세션 거부 시 완료 전환 안 됨(BLOCKER2)', (t) async {
    final c1 = s.confirmDraw(o1) as DrawCreated;
    s.markRevealStarted(c1.drawId);
    s.markRevealed(c1.drawId);
    await pumpTo(t, c1.drawId); // result stage
    expect(find.text('보관하기'), findsOneWidget);
    // 세션 교체 → c1 draw가 더 이상 active 아님(stale)
    s.reset();
    s.confirmDraw(o1);
    await t.tap(find.text('보관하기'));
    await t.pumpAndSettle();
    expect(find.text('오리파로 돌아가기'), findsNothing); // 완료 전환 X
    expect(find.text('보관하기'), findsOneWidget); // 여전히 액션 가능(재시도)
  });

  testWidgets('다시 뽑기 → clear + again 반환으로 draw 종료', (t) async {
    final c = s.confirmDraw(o1) as DrawCreated;
    s.markRevealStarted(c.drawId);
    s.markRevealed(c.drawId);
    await pumpTo(t, c.drawId);
    await t.tap(find.text('보관하기'));
    await t.pumpAndSettle();
    await t.tap(find.text('다시 뽑기'));
    await t.pumpAndSettle();
    expect(find.text('DETAIL'), findsOneWidget); // draw 종료(복귀)
    expect(s.activeDraw, isNull); // clear됨
  });
}
