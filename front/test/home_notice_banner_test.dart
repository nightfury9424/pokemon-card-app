import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/home_notice_banner.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';
import 'package:front/features/board/models/board_filter.dart';

/// fetchList 호출 횟수 카운트(refresh +1 검증).
class _CountRepo extends BoardRepository {
  int calls = 0;
  _CountRepo();
  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    String? q,
    bool pinnedOnly = false,
    int page = 0,
    int size = 20,
  }) async {
    calls++;
    return const BoardListResult(
      posts: [],
      page: 0,
      size: 5,
      totalPages: 0,
      totalElements: 0,
    );
  }
}

/// 완료 시점 제어(stale 방어 검증) — 각 fetchList 호출마다 Completer 누적.
class _GatedRepo extends BoardRepository {
  final List<Completer<BoardListResult>> gates = [];
  _GatedRepo();
  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    String? q,
    bool pinnedOnly = false,
    int page = 0,
    int size = 20,
  }) {
    final c = Completer<BoardListResult>();
    gates.add(c);
    return c.future;
  }
}

BoardListResult _one(BoardPost p) => BoardListResult(
  posts: [p],
  page: 0,
  size: 5,
  totalPages: 1,
  totalElements: 1,
);

/// 푸시된 라우트 캡처(상세를 mount 하지 않고 위젯만 검사 → 네트워크 회피).
class _Recorder extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushed.add(route);
  }
}

/// 네트워크 없는 fake — fetchList 호출 인자 캡처 + 정해진 목록/오류 반환.
class _FakeRepo extends BoardRepository {
  final List<BoardPost> posts;
  final bool fail;
  String? lastSection;
  String? lastType;
  bool? lastPinnedOnly;
  int? lastSize;
  _FakeRepo({this.posts = const [], this.fail = false});

  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    String? q,
    bool pinnedOnly = false,
    int page = 0,
    int size = 20,
  }) async {
    lastSection = section;
    lastType = type;
    lastPinnedOnly = pinnedOnly;
    lastSize = size;
    if (fail) throw Exception('network down');
    return BoardListResult(
      posts: posts,
      page: 0,
      size: size,
      totalPages: 1,
      totalElements: posts.length,
    );
  }
}

BoardPost _notice(
  String id,
  String title, {
  bool pinned = false,
  String type = 'notice',
}) => BoardPost.fromJson({
  'id': id,
  'type': type,
  'title': title,
  'body': 'b',
  'author': '운영팀',
  'createdAt': '2026-06-24T10:00:00',
  'isPinned': pinned,
});

Future<void> _pump(WidgetTester t, BoardRepository repo) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: HomeNoticeBanner(repository: repo)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('고정 공식글(핀 우선 첫 항목) 표시 + official/pinnedOnly 질의', (t) async {
    final repo = _FakeRepo(
      posts: [_notice('n1', '핀 공지', pinned: true), _notice('n2', '일반 공지')],
    );
    await _pump(t, repo);
    expect(find.text('핀 공지'), findsOneWidget); // 서버 순서 첫 항목
    expect(find.text('일반 공지'), findsNothing); // 배너는 첫 항목만
    expect(find.byIcon(Icons.campaign), findsOneWidget);
    expect(repo.lastSection, 'official');
    expect(repo.lastType, isNull); // ★type 미지정(공지/이벤트/패치 통합)
    expect(repo.lastPinnedOnly, isTrue); // ★고정된 공식글만
  });

  testWidgets('공지 0건 → 배너 숨김(SizedBox)', (t) async {
    await _pump(t, _FakeRepo(posts: const []));
    expect(find.byIcon(Icons.campaign), findsNothing);
    expect(find.byType(SizedBox), findsWidgets); // shrink
  });

  testWidgets('API 오류 → 배너 숨김(홈 비차단·가짜 공지 금지)', (t) async {
    await _pump(t, _FakeRepo(fail: true));
    expect(find.byIcon(Icons.campaign), findsNothing);
  });

  testWidgets('긴 제목 → overflow 없이 ellipsis(maxLines 1)', (t) async {
    final long = '아주 긴 공지 제목 ' * 30;
    await _pump(t, _FakeRepo(posts: [_notice('n1', long)]));
    // overflow 발생 시 pumpAndSettle 단계에서 FlutterError 가 터지므로, 여기 도달 = overflow 0.
    expect(find.byIcon(Icons.campaign), findsOneWidget);
    expect(find.text(long), findsOneWidget); // 전체 텍스트는 위젯에 보존(시각적으로만 ellipsis)
  });

  testWidgets('상세 영역 탭 → BoardDetailScreen 단일 push(postId 일치, 목록 push 0)', (
    t,
  ) async {
    final obs = await _pumpWithObserver(
      t,
      _FakeRepo(posts: [_notice('nX', '공지제목')]),
    );
    await t.tap(find.text('공지제목')); // 상세 영역(제목) 탭
    final routes = obs.pushed.whereType<MaterialPageRoute>().toList();
    expect(routes.length, 1); // 정확히 1회(형제 목록 버튼은 미발동)
    final w = routes.single.builder(
      t.element(find.byType(MaterialApp)),
    ); // mount 없이 위젯만 구성(네트워크 회피)
    expect(w, isA<BoardDetailScreen>());
    expect((w as BoardDetailScreen).postId, 'nX'); // 배너 공지 id 와 정확히 일치
    await t.pumpWidget(const SizedBox()); // pending 라우트 정리(상세 build 방지)
  });

  testWidgets('접근성: 상세/목록 형제 버튼 — 분리 노드·tap action·제목 포함 라벨·목록 44×44', (
    t,
  ) async {
    final handle = t.ensureSemantics();
    await _pump(t, _FakeRepo(posts: [_notice('nX', '점검 공지')]));

    // 상세 버튼: 라벨에 실제 제목 포함(정확 일치 = 목록 라벨과 병합 안 됨) + button + tap action + ≥44×44.
    final detail = find.bySemanticsLabel('공지 상세 보기: 점검 공지');
    expect(detail, findsOneWidget);
    final detailNode = t.getSemantics(detail);
    expect(detailNode.label, '공지 상세 보기: 점검 공지');
    final detailData = detailNode.getSemanticsData();
    expect(detailData.flagsCollection.isButton, isTrue);
    expect(detailData.hasAction(SemanticsAction.tap), isTrue);
    final detailSize = t.getSize(detail);
    expect(detailSize.width, greaterThanOrEqualTo(44));
    expect(detailSize.height, greaterThanOrEqualTo(44)); // ★상세 터치 높이 46 보장

    // 목록 버튼: 별개 노드(라벨 정확) + button + tap action + ≥44×44.
    final list = find.bySemanticsLabel('공지 목록 보기');
    expect(list, findsOneWidget);
    final listNode = t.getSemantics(list);
    expect(listNode.label, '공지 목록 보기');
    final listData = listNode.getSemanticsData();
    expect(listData.flagsCollection.isButton, isTrue);
    expect(listData.hasAction(SemanticsAction.tap), isTrue);
    final listSize = t.getSize(list);
    expect(listSize.width, greaterThanOrEqualTo(44));
    expect(listSize.height, greaterThanOrEqualTo(44));

    handle.dispose();
  });

  testWidgets('우측 화살표 탭 → BoardScreen(initialFilter.notice, 공지 목록) push', (t) async {
    final obs = await _pumpWithObserver(
      t,
      _FakeRepo(posts: [_notice('nX', '공지제목')]),
    );
    await t.tap(find.byIcon(Icons.chevron_right));
    final routes = obs.pushed.whereType<MaterialPageRoute>().toList();
    expect(
      routes.length,
      1,
    ); // ★정확히 1회 push — 중첩 GestureDetector 가 부모 배너 탭까지 발동시키지 않음
    final w = routes.single.builder(t.element(find.byType(MaterialApp)));
    expect(w, isA<BoardScreen>()); // 상세(BoardDetailScreen)가 아니라 목록만 열림
    expect((w as BoardScreen).initialFilter, BoardFilter.notice); // 공지 진입
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('IndexedStack 탭 재진입 — fetchList 재호출 없음(1회 유지), refresh 시에만 +1', (
    t,
  ) async {
    final repo = _CountRepo();
    final key = GlobalKey<HomeNoticeBannerState>();
    var idx = 0;
    await t.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (ctx, setState) => Scaffold(
            body: IndexedStack(
              index: idx,
              children: [
                HomeNoticeBanner(key: key, repository: repo),
                const Center(child: Text('다른탭 본문')),
              ],
            ),
            bottomNavigationBar: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => idx = 0),
                    child: const Text('홈탭'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => setState(() => idx = 1),
                    child: const Text('다른탭'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.calls, 1); // 홈 최초 진입
    await t.tap(find.text('다른탭'));
    await t.pumpAndSettle();
    await t.tap(find.text('홈탭'));
    await t.pumpAndSettle();
    expect(
      repo.calls,
      1,
    ); // ★재진입에도 1회 유지(IndexedStack keepalive = 중복 API 호출 없음)
    await key.currentState!.refresh();
    await t.pumpAndSettle();
    expect(repo.calls, 2); // pull-to-refresh 시에만 +1
  });

  testWidgets('refresh() → fetchList 추가 호출(+1), Future 완료 await 가능', (t) async {
    final repo = _CountRepo();
    final key = GlobalKey<HomeNoticeBannerState>();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeNoticeBanner(key: key, repository: repo),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(repo.calls, 1); // initState fetch
    await key.currentState!.refresh(); // Future<void> → 완료까지 await
    await t.pumpAndSettle();
    expect(repo.calls, 2); // pull-to-refresh 재조회
  });

  testWidgets('stale: 늦게 끝난 이전 요청이 최신 결과를 덮지 않음', (t) async {
    final repo = _GatedRepo();
    final key = GlobalKey<HomeNoticeBannerState>();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeNoticeBanner(key: key, repository: repo),
        ),
      ),
    );
    await t.pump(); // initState fetch → gates[0] 보류(reqId 1)
    key.currentState!.refresh(); // 2차 → gates[1] 보류(reqId 2)
    await t.pump();
    repo.gates[1].complete(_one(_notice('n2', '최신 공지'))); // 최신 먼저 완료
    await t.pumpAndSettle();
    expect(find.text('최신 공지'), findsOneWidget);
    repo.gates[0].complete(_one(_notice('n1', '오래된 공지'))); // 이전 요청 뒤늦게 완료
    await t.pumpAndSettle();
    expect(find.text('최신 공지'), findsOneWidget); // 여전히 최신(stale 폐기)
    expect(find.text('오래된 공지'), findsNothing);
  });
}

Future<_Recorder> _pumpWithObserver(
  WidgetTester t,
  BoardRepository repo,
) async {
  final obs = _Recorder();
  await t.pumpWidget(
    MaterialApp(
      navigatorObservers: [obs],
      home: Scaffold(body: HomeNoticeBanner(repository: repo)),
    ),
  );
  await t.pumpAndSettle();
  obs.pushed.clear(); // 초기 라우트 무시
  return obs;
}
