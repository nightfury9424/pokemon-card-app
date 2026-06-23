import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 홈 카루셀 탭 전환 회귀 — IndexedStack + 탭별 전용 PageController 패턴 검증.
///
/// 기존 버그: 단일 PageView 에 탭마다 controller 를 갈아끼워 전환 첫 프레임에 새 controller 가
/// 재부착되며 선택 카드 크기/peek 가 스냅. 수정: 탭별 PageView 분리 + IndexedStack →
/// 두 탭 모두 트리에 유지되어 controller 가 detach/reattach 되지 않고 각자 페이지가 보존됨.
///
/// (실제 HomeScreen 카루셀은 프로바이더·네트워크 의존이라 위젯테스트 불가 → 동일 구조 패턴으로
///  "전환해도 controller 유지·페이지 보존"을 회귀 검증. 최종 시각 확인은 실기기 IPA.)
void main() {
  testWidgets('IndexedStack 탭 전환 — 양쪽 controller 유지 + 각 탭 페이지 보존(스냅/초기화 없음)',
      (tester) async {
    final harness = _CarouselHarness();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: harness)));
    final state = tester.state<_CarouselHarnessState>(find.byType(_CarouselHarness));

    // 두 탭 PageView 가 모두 트리에 존재 → 양쪽 controller attach.
    expect(state.c0.hasClients, isTrue);
    expect(state.c1.hasClients, isTrue);

    // 탭0에서 스와이프(페이지 이동) 후 그 페이지 기록.
    await tester.drag(find.byKey(const Key('pv-0')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    final page0AfterSwipe = state.c0.page!.round();
    expect(page0AfterSwipe, isNot(_kStart), reason: '탭0 스와이프로 페이지 이동');

    // 탭1로 전환.
    await tester.tap(find.byKey(const Key('to-tab1')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '탭 전환 시 예외 없음');
    // ★전환해도 탭0 controller 가 detach 되지 않고 페이지 보존(재부착 스냅/초기화 없음).
    expect(state.c0.hasClients, isTrue);
    expect(state.c0.page!.round(), page0AfterSwipe, reason: '탭0 페이지 보존');

    // 탭1에서 스와이프 → 탭1만 이동, 탭0 불변.
    await tester.drag(find.byKey(const Key('pv-1')), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(state.c1.page!.round(), isNot(_kStart), reason: '탭1 스와이프 이동');
    expect(state.c0.page!.round(), page0AfterSwipe, reason: '탭1 스와이프가 탭0에 영향 없음');

    // 탭0 복귀 → 여전히 보존.
    await tester.tap(find.byKey(const Key('to-tab0')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(state.c0.page!.round(), page0AfterSwipe, reason: '탭0 복귀 시 페이지 보존');
  });

  testWidgets('연속 스와이프 — 예외 없이 페이지 누적 이동', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _CarouselHarness())));
    final state = tester.state<_CarouselHarnessState>(find.byType(_CarouselHarness));
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byKey(const Key('pv-0')), const Offset(-400, 0));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    expect(state.c0.page!.round(), greaterThan(_kStart), reason: '연속 스와이프 누적');
  });
}

const int _kStart = 500000;

/// 수정 구조와 동일: 탭별 전용 PageController(viewportFraction 0.6) + IndexedStack.
class _CarouselHarness extends StatefulWidget {
  @override
  State<_CarouselHarness> createState() => _CarouselHarnessState();
}

class _CarouselHarnessState extends State<_CarouselHarness> {
  int tab = 0;
  final c0 = PageController(viewportFraction: 0.6, initialPage: _kStart);
  final c1 = PageController(viewportFraction: 0.6, initialPage: _kStart);

  @override
  void dispose() {
    c0.dispose();
    c1.dispose();
    super.dispose();
  }

  Widget _pv(Key key, PageController c) => SizedBox(
        height: 200,
        child: PageView.builder(
          key: key,
          controller: c,
          itemCount: 1000000,
          itemBuilder: (_, i) => Container(
            margin: const EdgeInsets.all(4),
            color: Colors.blue,
            child: Center(child: Text('$i')),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            TextButton(
                key: const Key('to-tab0'),
                onPressed: () => setState(() => tab = 0),
                child: const Text('t0')),
            TextButton(
                key: const Key('to-tab1'),
                onPressed: () => setState(() => tab = 1),
                child: const Text('t1')),
          ],
        ),
        IndexedStack(
          index: tab,
          children: [
            KeyedSubtree(
                key: const PageStorageKey('s0'), child: _pv(const Key('pv-0'), c0)),
            KeyedSubtree(
                key: const PageStorageKey('s1'), child: _pv(const Key('pv-1'), c1)),
          ],
        ),
      ],
    );
  }
}
