import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/board_compose_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 공통 화면 이탈 정책 — 상태 변경 요청(좋아요는 board_like_test) 진행 중엔 뒤로가기 차단.
/// 여기선 댓글 작성·댓글 삭제·게시글 삭제·작성 저장을 검증. 지연 요청 중 pop 차단 → 완료 후 가능.

class _ExitRepo extends BoardRepository {
  final BoardPost detail;
  final Duration delay = const Duration(milliseconds: 400); // 다이얼로그 dismiss 보다 길게(이탈 차단 관찰)
  int createComments = 0;
  int deleteComments = 0;
  int deletePosts = 0;
  int createPosts = 0;
  _ExitRepo({required this.detail});

  @override
  Future<BoardPost?> fetchDetail(String id) async => detail;

  @override
  Future<String> createComment(String postId,
      {required String content, String? parentCommentId}) async {
    createComments++;
    await Future<void>.delayed(delay);
    return 'c-new';
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteComments++;
    await Future<void>.delayed(delay);
  }

  @override
  Future<void> deletePost(String postId) async {
    deletePosts++;
    await Future<void>.delayed(delay);
  }

  @override
  Future<String> createPost(
      {required String type,
      required String title,
      required String content,
      List<String> imageUploadIds = const []}) async {
    createPosts++;
    await Future<void>.delayed(delay);
    return 'p-new';
  }
}

BoardPost _free({List<BoardComment> comments = const [], bool canEdit = false, bool canDelete = false}) =>
    BoardPost(
      id: 'p1',
      type: BoardType.free,
      title: '제목',
      body: '본문',
      author: '글쓴이',
      createdAt: DateTime(2026, 6, 24, 10),
      comments: comments,
      canEdit: canEdit,
      canDelete: canDelete,
    );

BoardComment _myComment() => BoardComment(
      id: 'm1', author: '나', body: '내댓글', createdAt: DateTime(2026, 6, 24, 10),
      mine: true, canDelete: true);

Future<void> _openDetail(WidgetTester t, BoardRepository r, void Function(Object?) sink) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => sink(await Navigator.of(ctx).push(
                MaterialPageRoute(builder: (_) => BoardDetailScreen(postId: 'p1', repository: r)))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('댓글 작성 중 뒤로 차단 → 완료 후 뒤로=changed', (t) async {
    final repo = _ExitRepo(detail: _free());
    Object? pop = 'S';
    await _openDetail(t, repo, (v) => pop = v);

    await t.enterText(find.byType(TextField), '댓글');
    await t.pump();
    await t.tap(find.byIcon(Icons.send_rounded)); // 전송(지연)
    await t.pump();
    await t.tap(find.byType(BackButton)); // 요청 중 뒤로
    await t.pump();
    expect(find.byType(BoardDetailScreen), findsOneWidget); // 안 닫힘
    expect(pop, 'S');

    await t.pumpAndSettle(); // 완료
    expect(repo.createComments, 1);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(pop, 'changed');
  });

  testWidgets('댓글 삭제 중 뒤로 차단 → 완료 후 가능', (t) async {
    final repo = _ExitRepo(detail: _free(comments: [_myComment()]));
    Object? pop = 'S';
    await _openDetail(t, repo, (v) => pop = v);

    await t.tap(find.text('삭제')); // 댓글 액션
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('삭제'))); // 확인 → 삭제(지연)
    await t.pump(const Duration(milliseconds: 250)); // 다이얼로그 dismiss
    await t.tap(find.byType(BackButton)); // 요청 중 뒤로
    await t.pump();
    expect(find.byType(BoardDetailScreen), findsOneWidget);
    expect(pop, 'S');

    await t.pumpAndSettle();
    expect(repo.deleteComments, 1);
    await t.tap(find.byType(BackButton));
    await t.pumpAndSettle();
    expect(pop, 'changed');
  });

  testWidgets('게시글 삭제 중 뒤로 차단 → 완료 시 deleted pop', (t) async {
    final repo = _ExitRepo(detail: _free(canEdit: true, canDelete: true));
    Object? pop = 'S';
    await _openDetail(t, repo, (v) => pop = v);

    await t.tap(find.byIcon(Icons.more_vert)); // ⋯ 메뉴
    await t.pumpAndSettle();
    await t.tap(find.text('삭제')); // 메뉴 항목
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('삭제'))); // 확인 → 삭제(지연)
    await t.pump(const Duration(milliseconds: 250));
    await t.tap(find.byType(BackButton)); // 요청 중 뒤로
    await t.pump();
    expect(find.byType(BoardDetailScreen), findsOneWidget); // 안 닫힘

    await t.pumpAndSettle(); // 완료 → force pop('deleted')
    expect(repo.deletePosts, 1);
    expect(pop, 'deleted');
  });

  testWidgets('작성 저장 중 뒤로 차단 → 완료 시 postId pop', (t) async {
    final repo = _ExitRepo(detail: _free());
    Object? pop = 'S';
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => pop = await Navigator.of(ctx).push(
                  MaterialPageRoute(builder: (_) => BoardComposeScreen(repository: repo))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField).at(0), '제목');
    await t.enterText(find.byType(TextField).at(1), '본문');
    await t.pump();
    await t.tap(find.text('등록')); // 저장(지연)
    await t.pump();
    await t.tap(find.byType(BackButton)); // 저장 중 뒤로
    await t.pump();
    expect(find.byType(BoardComposeScreen), findsOneWidget); // 안 닫힘(폐기 다이얼로그도 없음)
    expect(pop, 'S');

    await t.pumpAndSettle(); // 완료 → pop(postId)
    expect(repo.createPosts, 1);
    expect(pop, 'p-new');
  });
}
