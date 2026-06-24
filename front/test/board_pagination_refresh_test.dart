import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 슬라이스7 후속 — 무플래시 재조회(_silentReload)가 로드된 페이지 범위를 보존하는지.
/// 40개 게시글, pinnedId 가 있으면 최상단으로(서버 핀 정렬 모사). page 별 조회 이력 기록.
class _PagedRepo extends BoardRepository {
  String pinnedId = '';
  final List<int> pageHistory = [];

  List<BoardPost> _all() {
    final ids = List.generate(40, (i) => 'p$i');
    if (pinnedId.isNotEmpty) {
      ids.remove(pinnedId);
      ids.insert(0, pinnedId);
    }
    return ids
        .map((id) => BoardPost(
              id: id,
              type: BoardType.free,
              title: id,
              body: 'b',
              author: 'u',
              createdAt: DateTime(2026, 1, 1),
              isPinned: id == pinnedId,
            ))
        .toList();
  }

  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    int page = 0,
    int size = 20,
  }) async {
    pageHistory.add(page);
    final all = _all();
    final start = page * size;
    final end = (start + size) > all.length ? all.length : (start + size);
    final slice = start >= all.length ? <BoardPost>[] : all.sublist(start, end);
    return BoardListResult(
        posts: slice, page: page, size: size, totalPages: 2, totalElements: all.length);
  }
}

void main() {
  group('mergeBoardPages', () {
    BoardPost p(String id) =>
        BoardPost(id: id, type: BoardType.free, title: id, body: '', author: '', createdAt: DateTime(2026, 1, 1));
    test('순서 병합 + postId 중복 제거', () {
      final merged = mergeBoardPages([
        [p('a'), p('b')],
        [p('b'), p('c')], // b 중복(핀 이동 모사)
      ]);
      expect(merged.map((e) => e.id).toList(), ['a', 'b', 'c']); // 순서 유지·중복 0·누락 0
    });
    test('빈 페이지 안전', () {
      expect(mergeBoardPages([[], []]), isEmpty);
    });
  });

  testWidgets('resume 시 로드된 페이지 범위 유지(첫20개로 축소 안 함) + 핀 반영', (t) async {
    final repo = _PagedRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    final list = find.descendant(of: find.byType(RefreshIndicator), matching: find.byType(Scrollable));

    // page 1 추가 로드 — 마지막 항목까지 스크롤
    await t.scrollUntilVisible(find.text('p39'), 400, scrollable: list, maxScrolls: 60);
    await t.pumpAndSettle();
    expect(find.text('p39'), findsOneWidget); // 40개 로드됨
    expect(repo.pageHistory, containsAllInOrder([0, 1]));

    // 관리자 핀 변경(p30 최상단) + 앱 resume
    repo.pinnedId = 'p30';
    repo.pageHistory.clear();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();

    // ★범위(0,1) 재조회 — page 0만이 아님
    expect(repo.pageHistory, containsAllInOrder([0, 1]));
    // 범위 유지: p39 여전히 도달 가능(첫 20개로 축소됐다면 실패)
    await t.scrollUntilVisible(find.text('p39'), 400, scrollable: list, maxScrolls: 60);
    expect(find.text('p39'), findsOneWidget);
    // 핀 반영: 위로 스크롤 → p30 표시(최상단)
    await t.scrollUntilVisible(find.text('p30'), -400, scrollable: list, maxScrolls: 60);
    expect(find.text('p30'), findsOneWidget);
  });
}
