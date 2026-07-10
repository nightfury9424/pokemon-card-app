import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/reveal_models.dart';
import 'package:front/features/oripa/data/reveal_fixtures.dart';
import 'package:front/features/oripa/draw/reveal_view.dart';

/// RevealView 애니 계약 (spec §B-2·B-5): 오프닝 락 → clue 자동+탭가속 → HERO → heroHold.
void main() {
  final descriptor = buildRevealDescriptor(RevealFixtures.rawHit, number: 47);
  // clue: RAW · SAR · 테라스탈 페스타 ex · 블래키 ex (4)
  const config = RevealConfig(); // openingLock 900 / beat 650 / pause 260 / heroHold 700

  String? clue(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('reveal_clue'))).data;

  Future<void> mount(
    WidgetTester t, {
    bool startAtHero = false,
    bool skipHold = false,
    VoidCallback? onHero,
    VoidCallback? onResult,
  }) {
    return t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RevealView(
          descriptor: descriptor,
          config: config,
          hero: const SizedBox(key: Key('hero'), width: 20, height: 20),
          startAtHero: startAtHero,
          skipHold: skipHold,
          onHeroShown: onHero ?? () {},
          onResultReady: onResult ?? () {},
        ),
      ),
    ));
  }

  testWidgets('오프닝 락 → openingLock 후 첫 clue(RAW)', (t) async {
    await mount(t);
    expect(clue(t), ''); // 오프닝: clue 없음
    await t.pump(const Duration(milliseconds: 901));
    expect(clue(t), 'RAW');
    await t.pump(const Duration(milliseconds: 2000)); // 잔여 타이머 정리
  });

  testWidgets('clue 자동 진행 (RAW→SAR)', (t) async {
    await mount(t);
    await t.pump(const Duration(milliseconds: 901)); // RAW
    await t.pump(const Duration(milliseconds: 911)); // beat+pause
    expect(clue(t), 'SAR');
    await t.pump(const Duration(milliseconds: 3000));
  });

  testWidgets('탭 가속 — 현재 clue 즉시 완료 → 다음', (t) async {
    await mount(t);
    await t.pump(const Duration(milliseconds: 901)); // RAW
    await t.tap(find.byType(RevealView));
    await t.pump();
    expect(clue(t), 'SAR');
    await t.pump(const Duration(milliseconds: 3000));
  });

  testWidgets('HERO 도달 → onHeroShown, heroHold 후 onResultReady', (t) async {
    var hero = false, result = false;
    await mount(t, onHero: () => hero = true, onResult: () => result = true);
    await t.pump(const Duration(milliseconds: 901)); // RAW (_beat=0)
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byType(RevealView));
      await t.pump();
    }
    expect(find.byKey(const Key('hero')), findsOneWidget);
    expect(hero, isTrue); // HERO 실제 렌더 후 호출
    expect(result, isFalse); // heroHold 중 → 아직
    await t.pump(const Duration(milliseconds: 701));
    expect(result, isTrue);
  });

  testWidgets('startAtHero — clue 생략, HERO 즉시 + onHeroShown', (t) async {
    var hero = false;
    await mount(t, startAtHero: true, onHero: () => hero = true);
    await t.pump(); // postFrame
    expect(find.byKey(const Key('hero')), findsOneWidget);
    expect(find.byKey(const Key('reveal_clue')), findsNothing);
    expect(hero, isTrue);
    await t.pump(const Duration(milliseconds: 701)); // heroHold 정리
  });

  testWidgets('skipHold — HERO 후 heroHold 없이 즉시 onResultReady', (t) async {
    var result = false;
    await mount(t,
        startAtHero: true, skipHold: true, onResult: () => result = true);
    await t.pump(); // postFrame → hero → skipHold → onResultReady
    expect(result, isTrue);
  });
}
