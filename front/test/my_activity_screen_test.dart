import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/profile/my_activity_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 내 활동 화면 — 2탭(내가 쓴 글/댓글 단 글)·목록 렌더·탭 전환·빈 상태·overflow 0.
/// 서버 정렬/필터는 백엔드 통합테스트가 담당. 여기선 화면 동작만(가짜 repo).
class _FakeRepo extends BoardRepository {
  final List<BoardPost> posts;
  final List<BoardPost> commented;
  _FakeRepo({this.posts = const [], this.commented = const []});

  @override
  Future<BoardListResult> fetchMyPosts({int page = 0, int size = 20}) async =>
      BoardListResult(
          posts: page == 0 ? posts : const [],
          page: page, size: size, totalPages: 1, totalElements: posts.length);

  @override
  Future<BoardListResult> fetchMyCommentedPosts({int page = 0, int size = 20}) async =>
      BoardListResult(
          posts: page == 0 ? commented : const [],
          page: page, size: size, totalPages: 1, totalElements: commented.length);
}

BoardPost _p(String id, String title, String author) => BoardPost(
      id: id, type: BoardType.free, title: title, body: 'body',
      author: author, createdAt: DateTime(2026, 6, 27),
      likeCount: 0, viewCount: 0, listCommentCount: 0,
    );

void main() {
  testWidgets('2탭 라벨 + 내가 쓴 글 목록 렌더', (t) async {
    await t.pumpWidget(MaterialApp(
      home: MyActivityScreen(
        repository: _FakeRepo(posts: [_p('1', '내 글 하나', 'me'), _p('2', '내 글 둘', 'me')]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('내가 쓴 글'), findsOneWidget);
    expect(find.text('내가 댓글 단 글'), findsOneWidget);
    expect(find.text('내 글 하나'), findsOneWidget);
    expect(find.text('내 글 둘'), findsOneWidget);
  });

  testWidgets('탭 전환 → 내가 댓글 단 글 목록 표시', (t) async {
    await t.pumpWidget(MaterialApp(
      home: MyActivityScreen(
        repository: _FakeRepo(posts: [_p('1', '내 글', 'me')], commented: [_p('9', '댓글 단 글', 'other')]),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('내 글'), findsOneWidget);
    await t.tap(find.text('내가 댓글 단 글'));
    await t.pumpAndSettle();
    expect(find.text('댓글 단 글'), findsOneWidget);
  });

  testWidgets('빈 상태 문구(각 탭별)', (t) async {
    await t.pumpWidget(MaterialApp(home: MyActivityScreen(repository: _FakeRepo())));
    await t.pumpAndSettle();
    expect(find.text('아직 작성한 글이 없어요'), findsOneWidget);
    await t.tap(find.text('내가 댓글 단 글'));
    await t.pumpAndSettle();
    expect(find.text('아직 댓글을 남긴 글이 없어요'), findsOneWidget);
  });

  for (final w in <double>[375, 430]) {
    testWidgets('overflow 0 — ${w.toInt()}px (긴 제목/닉네임)', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = Size(w, 800);
      addTearDown(() => t.view.resetPhysicalSize());
      await t.pumpWidget(MaterialApp(
        home: MyActivityScreen(
          repository: _FakeRepo(posts: [_p('1', '아주 긴 제목 입니다 ' * 6, '아주긴닉네임' * 3)]),
        ),
      ));
      await t.pumpAndSettle();
      // 오버플로 발생 시 pump 단계에서 FlutterError 자동 실패.
      expect(find.text('내가 쓴 글'), findsOneWidget);
    });
  }
}
