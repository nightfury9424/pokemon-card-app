import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';
import 'package:front/features/board/models/board_filter.dart';

/// 슬라이스4B 목록 레이아웃 — 7 pill 탭 + 목록 아이템이 375/430px 에서 오버플로 0.
/// (오버플로 발생 시 Flutter 가 FlutterError 를 던져 테스트 자동 실패. 긴 제목·긴 닉네임으로 압박.)
class _Repo extends BoardRepository {
  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    String? q,
    bool pinnedOnly = false,
    int page = 0,
    int size = 20,
  }) async {
    final posts = page > 0
        ? <BoardPost>[]
        : [
            BoardPost(
                id: '1',
                type: BoardType.notice,
                title: '아주 긴 공지 제목 입니다 ' * 4,
                body: '긴 본문 미리보기 ' * 12,
                author: '운영팀',
                createdAt: DateTime(2026, 1, 1),
                viewCount: 1234567,
                isPinned: true,
                comments: List.generate(99, _c)),
            BoardPost(
                id: '2',
                type: BoardType.scamAlert,
                title: '사기주의 긴 제목 테스트',
                body: '본문',
                author: '아주아주긴닉네임입니다과연어디까지',
                createdAt: DateTime(2026, 1, 1),
                viewCount: 999999,
                likeCount: 0,
                comments: const []),
          ];
    return BoardListResult(
        posts: posts, page: page, size: size, totalPages: 1, totalElements: posts.length);
  }
}

BoardComment _c(int i) =>
    BoardComment(id: 'c$i', author: 'u', body: 'x', createdAt: DateTime(2026, 1, 1));

void main() {
  for (final w in <double>[375, 430]) {
    testWidgets('목록 오버플로 0 — ${w.toInt()}px (7 pill 탭·긴 제목/닉네임)', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 900);
      addTearDown(() => t.view.resetPhysicalSize());
      await t.pumpWidget(MaterialApp(home: BoardScreen(repository: _Repo())));
      await t.pumpAndSettle();
      // 오버플로 없으면 여기 도달(있으면 위에서 자동 실패). 7탭 라벨 렌더 확인.
      for (final f in BoardFilter.values) {
        expect(find.text(f.label), findsWidgets);
      }
    });
  }

  testWidgets('#6 카운터: likeCount 0 도 좋아요 표시 + 순서 좋아요→댓글→조회 (공지/비공식 동일·검색결과 동일 빌더)', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(430, 900);
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: _Repo())));
    await t.pumpAndSettle();
    // ★조건부 숨김 제거 — likeCount 0(두 글 다 0)이어도 좋아요(빈 하트) 표시. 댓글·조회도 항상.
    expect(find.byIcon(Icons.favorite_border), findsWidgets);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsWidgets);
    expect(find.byIcon(Icons.visibility_outlined), findsWidgets);
    // ★순서: 첫 글 기준 좋아요 → 댓글 → 조회 (x 좌표 좌→우)
    final likeX = t.getCenter(find.byIcon(Icons.favorite_border).first).dx;
    final commentX = t.getCenter(find.byIcon(Icons.chat_bubble_outline_rounded).first).dx;
    final viewX = t.getCenter(find.byIcon(Icons.visibility_outlined).first).dx;
    expect(likeX, lessThan(commentX), reason: '좋아요가 댓글보다 왼쪽');
    expect(commentX, lessThan(viewX), reason: '댓글이 조회보다 왼쪽');
  });
}
