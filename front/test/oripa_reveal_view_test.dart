import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/reveal_models.dart';
import 'package:front/features/oripa/data/reveal_fixtures.dart';
import 'package:front/features/oripa/draw/reveal_view.dart';

/// RevealView 애니 + 안전 계약 (spec §B-2·B-5, GPT 안전계약).
void main() {
  final descriptor = buildRevealDescriptor(RevealFixtures.rawHit, number: 47);
  // clue: RAW · SAR · 테라스탈 페스타 ex · 블래키 ex (4)

  String? clue(WidgetTester t) =>
      t.widget<Text>(find.byKey(const Key('reveal_clue'))).data;

  Future<void> mount(
    WidgetTester t, {
    RevealEntryMode mode = RevealEntryMode.fresh,
    RevealConfig config = const RevealConfig(), // 900/650/260/700
    VoidCallback? onHero,
    VoidCallback? onResult,
  }) {
    return t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RevealView(
          descriptor: descriptor,
          config: config,
          hero: const SizedBox(key: Key('hero'), width: 20, height: 20),
          entryMode: mode,
          onHeroShown: onHero ?? () {},
          onResultReady: onResult ?? () {},
        ),
      ),
    ));
  }

  // 남은 타이머/애니 정리(pending timer 방지)
  Future<void> settle(WidgetTester t) =>
      t.pump(const Duration(milliseconds: 6000));

  testWidgets('오프닝 락 → openingLock 후 첫 clue(RAW)', (t) async {
    await mount(t);
    expect(clue(t), '');
    await t.pump(const Duration(milliseconds: 901));
    expect(clue(t), 'RAW');
    await settle(t);
  });

  testWidgets('clue 자동 진행 (RAW→SAR)', (t) async {
    await mount(t);
    await t.pump(const Duration(milliseconds: 901));
    await t.pump(const Duration(milliseconds: 911));
    expect(clue(t), 'SAR');
    await settle(t);
  });

  testWidgets('탭 가속 — 현재 clue 즉시 완료 → 다음', (t) async {
    await mount(t);
    await t.pump(const Duration(milliseconds: 901));
    await t.tap(find.byType(RevealView));
    await t.pump();
    expect(clue(t), 'SAR');
    await settle(t);
  });

  testWidgets('HERO 도달 → onHeroShown, heroHold 후 onResultReady', (t) async {
    var hero = false, result = false;
    await mount(t, onHero: () => hero = true, onResult: () => result = true);
    await t.pump(const Duration(milliseconds: 901));
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byType(RevealView));
      await t.pump();
    }
    expect(find.byKey(const Key('hero')), findsOneWidget);
    expect(hero, isTrue);
    expect(result, isFalse);
    await t.pump(const Duration(milliseconds: 701));
    expect(result, isTrue);
  });

  testWidgets('committedRecovery — clue 생략, HERO+onHeroShown', (t) async {
    var hero = false;
    await mount(t, mode: RevealEntryMode.committedRecovery, onHero: () => hero = true);
    await t.pump();
    expect(find.byKey(const Key('hero')), findsOneWidget);
    expect(find.byKey(const Key('reveal_clue')), findsNothing);
    expect(hero, isTrue);
    await t.pump(const Duration(milliseconds: 701));
  });

  testWidgets('revealedRecovery — 결과 즉시, onHeroShown 재호출 금지', (t) async {
    var hero = false, result = false;
    await mount(t,
        mode: RevealEntryMode.revealedRecovery,
        onHero: () => hero = true,
        onResult: () => result = true);
    await t.pump();
    expect(result, isTrue);
    expect(hero, isFalse); // ★ 이미 REVEALED → onHeroShown 재호출 안 함
  });

  testWidgets('onHeroShown/onResultReady exactly-once (탭 연타 중복 없음)', (t) async {
    var heroCount = 0, resultCount = 0;
    await mount(t, onHero: () => heroCount++, onResult: () => resultCount++);
    await t.pump(const Duration(milliseconds: 901));
    for (var i = 0; i < 10; i++) {
      await t.tap(find.byType(RevealView));
      await t.pump();
    }
    expect(heroCount, 1);
    await t.pump(const Duration(milliseconds: 701));
    for (var i = 0; i < 5; i++) {
      await t.tap(find.byType(RevealView));
      await t.pump();
    }
    expect(resultCount, 1);
    expect(heroCount, 1);
  });

  testWidgets('HERO 탭은 heroHold 단축 안 함', (t) async {
    var result = false;
    await mount(t, onResult: () => result = true);
    await t.pump(const Duration(milliseconds: 901));
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byType(RevealView));
      await t.pump();
    }
    expect(find.byKey(const Key('hero')), findsOneWidget);
    await t.tap(find.byType(RevealView)); // HERO 탭
    await t.pump(const Duration(milliseconds: 699));
    expect(result, isFalse); // 탭해도 hold 안 줄어듦
    await t.pump(const Duration(milliseconds: 2));
    expect(result, isTrue);
  });

  testWidgets('dispose 후 콜백 없음 + 예외 없음', (t) async {
    var heroCount = 0, resultCount = 0;
    await mount(t, onHero: () => heroCount++, onResult: () => resultCount++);
    await t.pump(const Duration(milliseconds: 901)); // clue 진행 중
    await t.pumpWidget(const MaterialApp(home: Scaffold())); // RevealView dispose
    await t.pump(const Duration(milliseconds: 6000)); // 남은 타이머 경과
    expect(heroCount, 0);
    expect(resultCount, 0);
  });

  testWidgets('reduceMotion — 정보/콜백 순서 유지, 결과 직행 없음', (t) async {
    final order = <String>[];
    await mount(t,
        config: const RevealConfig(reduceMotion: true),
        onHero: () => order.add('hero'),
        onResult: () => order.add('result'));
    await t.pump(const Duration(milliseconds: 901));
    expect(clue(t), 'RAW'); // clue 순서 유지
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byType(RevealView));
      await t.pump();
    }
    expect(order, ['hero']); // 결과 직행 안 함
    await t.pump(const Duration(milliseconds: 701));
    expect(order, ['hero', 'result']); // 순서 유지
  });
}
