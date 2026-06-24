import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/home_notice_banner.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// fetchList 호출 횟수 카운트(refresh +1 검증).
class _CountRepo extends BoardRepository {
  int calls = 0;
  _CountRepo();
  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
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
  int? lastSize;
  _FakeRepo({this.posts = const [], this.fail = false});

  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    int page = 0,
    int size = 20,
  }) async {
    lastSection = section;
    lastType = type;
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
  testWidgets('첫 유효 공지(서버 핀 우선 순서의 첫 항목) 표시 + official/notice 질의', (t) async {
    final repo = _FakeRepo(
      posts: [_notice('n1', '핀 공지', pinned: true), _notice('n2', '일반 공지')],
    );
    await _pump(t, repo);
    expect(find.text('핀 공지'), findsOneWidget); // 서버 순서 첫 항목
    expect(find.text('일반 공지'), findsNothing); // 배너는 첫 항목만
    expect(find.byIcon(Icons.campaign), findsOneWidget);
    expect(repo.lastSection, 'official');
    expect(repo.lastType, 'notice');
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

  testWidgets('배너 본문 탭 → 해당 postId 의 BoardDetailScreen push', (t) async {
    final obs = await _pumpWithObserver(
      t,
      _FakeRepo(posts: [_notice('nX', '공지제목')]),
    );
    await t.tap(find.text('공지제목')); // 본문(제목) 탭 → body onTap
    final route = obs.pushed.whereType<MaterialPageRoute>().last;
    final w = route.builder(
      t.element(find.byType(MaterialApp)),
    ); // mount 없이 위젯만 구성(네트워크 회피)
    expect(w, isA<BoardDetailScreen>());
    expect((w as BoardDetailScreen).postId, 'nX'); // 배너 공지 id 와 정확히 일치
    await t.pumpWidget(const SizedBox()); // pending 라우트 정리(상세 build 방지)
  });

  testWidgets('우측 화살표 탭 → BoardScreen(initialTab 0, 공지 목록) push', (t) async {
    final obs = await _pumpWithObserver(
      t,
      _FakeRepo(posts: [_notice('nX', '공지제목')]),
    );
    await t.tap(find.byIcon(Icons.chevron_right));
    final route = obs.pushed.whereType<MaterialPageRoute>().last;
    final w = route.builder(t.element(find.byType(MaterialApp)));
    expect(w, isA<BoardScreen>());
    expect((w as BoardScreen).initialTab, 0); // 공지 탭 진입
    await t.pumpWidget(const SizedBox());
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
