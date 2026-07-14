// 오리파 리빌 Phase 1 · Step 1 검증 — 봉인 카드팩 + 상단 절취.
// 1) 정지 프레임 골든: 닫힌 팩 / 절취 중 / 절취 완료 (실제 렌더 — 폰트/아이콘 tofu 없음)
// 2) 반응형: 작은/큰 화면에서 팩 폭이 화면폭 62~70% + aspect 유지
// 3) 중심 불변: 실제 OripaDrawScreen에서 extracting → peeling 전환 시 팩 글로벌 중심 ≤2px
//
// 프레임 갱신: flutter test test/oripa/oripa_sealed_pack_golden.dart --update-goldens
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/oripa/data/oripa_mock.dart';
import 'package:front/features/oripa/data/oripa_session.dart';
import 'package:front/features/oripa/draw/oripa_draw_screen.dart';
import 'package:front/features/oripa/draw/oripa_sealed_pack.dart';

Future<void> _loadFont() async {
  final bytes = File('/System/Library/Fonts/Supplemental/AppleGothic.ttf')
      .readAsBytesSync();
  await (FontLoader('AppleGothic')
        ..addFont(Future.value(ByteData.view(bytes.buffer))))
      .load();
}

ThemeData _theme() =>
    ThemeData(fontFamily: 'AppleGothic', useMaterial3: true);

// 사용 가능 너비를 availW로 제한한 다크 스테이지 위 중앙 정렬(loose 제약 → 팩이 스스로 폭 산출).
Widget _stage({required double availW, required double tearProgress}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme(),
    home: Scaffold(
      backgroundColor: const Color(0xFF0A0B10),
      body: Center(
        child: SizedBox(
          width: availW,
          child: Center(
            child: OripaSealedPack(
              title: '151 마스터볼 넘버 오리파',
              number: 47,
              tearProgress: tearProgress,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont();
  });

  // ── 정지 프레임 골든 (availW 360 → 팩 폭 ≈237) ──
  Future<void> frame(WidgetTester t, double tearProgress, String file) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(420, 520) * 2.0;
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(_stage(availW: 360, tearProgress: tearProgress));
    await t.runAsync(() async {
      for (final n in ['base', 'open_body', 'top_strip', 'mouth_shadow']) {
        await precacheImage(AssetImage('assets/oripa/packs/navy/$n.png'),
            t.element(find.byType(OripaSealedPack)));
      }
    });
    await t.pumpAndSettle();
    await expectLater(find.byType(OripaSealedPack), matchesGoldenFile(file));
  }

  testWidgets('프레임 01 — 닫힌 카드팩', (t) async {
    await frame(t, 0.0, 'goldens/pack_01_closed.png');
  });
  testWidgets('프레임 02 — 상단 절취 중(약 55%)', (t) async {
    await frame(t, 0.55, 'goldens/pack_02_tearing.png');
  });
  testWidgets('프레임 03 — 절취 완료(스트립 분리)', (t) async {
    await frame(t, 1.0, 'goldens/pack_03_torn.png');
  });

  // ── 반응형: 작은/큰 화면에서 화면폭 62~70% + aspect 유지 ──
  Future<Size> packSize(WidgetTester t, double availW) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = Size(availW + 80, 760) * 2.0;
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(_stage(availW: availW, tearProgress: 0));
    await t.pumpAndSettle();
    return t.getSize(find.byType(OripaSealedPack));
  }

  testWidgets('반응형 — 작은 화면(360) 폭 62~70% + aspect', (t) async {
    final s = await packSize(t, 360);
    expect(s.width, closeTo(OripaSealedPack.widthFor(360), 0.5)); // 237.6
    expect(s.width / 360, inInclusiveRange(0.62, 0.70));
    expect(s.height, closeTo(s.width * OripaSealedPack.aspectRatio, 0.5));
  });

  testWidgets('반응형 — 큰 화면(430) 폭 62~70% + aspect', (t) async {
    final s = await packSize(t, 430);
    expect(s.width, closeTo(OripaSealedPack.widthFor(430), 0.5)); // 283.8
    expect(s.width / 430, inInclusiveRange(0.62, 0.70));
    expect(s.height, closeTo(s.width * OripaSealedPack.aspectRatio, 0.5));
  });

  testWidgets('반응형 — 초소형 화면은 minWidth로 clamp', (t) async {
    final s = await packSize(t, 260); // 0.66*260=171.6 < min196 → 196
    expect(s.width, closeTo(OripaSealedPack.minWidth, 0.5));
  });

  // ── 중심 불변: 실제 OripaDrawScreen에서 extracting → peeling 전환 ──
  // route completed 후 추출 시작 → 완료 시 peeling 전환. 두 stage에서 팩 글로벌 중심 측정.
  testWidgets('실제 draw 화면 — extracting↔peeling 팩 중심 ≤2px', (t) async {
    final o = OripaMock.oripaById('o1');
    final outcome = OripaSession.instance.confirmDraw(o);
    expect(outcome, isA<DrawCreated>(),
        reason: 'draw 시딩 실패(포인트/매진): $outcome');
    final drawId = (outcome as DrawCreated).drawId;

    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(390, 844) * 2.0; // iPhone 논리폭 390
    addTearDown(() => t.view.resetPhysicalSize());

    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(),
      home: OripaDrawScreen(oripaId: o.oripaId, drawId: drawId),
    ));

    await t.pump(); // postFrame: route completed 확인 → 추출 스케줄(100ms)
    await t.pump(const Duration(milliseconds: 160)); // 추출 시작(진행 중)
    expect(find.byType(OripaSealedPack), findsOneWidget,
        reason: 'extracting에서 팩 미표시 — 추출 시작 안 됨');
    final cExtract = t.getCenter(find.byType(OripaSealedPack));

    await t.pump(const Duration(milliseconds: 1000)); // 추출 완료 → peeling
    await t.pump();
    expect(find.byType(OripaSealedPack), findsOneWidget);
    final cPeel = t.getCenter(find.byType(OripaSealedPack));

    expect((cPeel - cExtract).distance, lessThan(2.0),
        reason: 'extracting→peeling 팩 중심 이동: $cExtract → $cPeel');
  });
}
