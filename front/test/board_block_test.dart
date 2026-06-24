import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 게시판 차단(신고 없이) UI — canBlock 게이팅 + 확인 다이얼로그 + board-post/comment 차단 호출 검증.
class _BlockRepo extends BoardRepository {
  final BoardPost post;
  String? lastBlockedPost;
  String? lastBlockedComment;
  _BlockRepo(this.post);
  @override
  Future<BoardPost?> fetchDetail(String id) async => post;
  @override
  Future<void> blockPostAuthor(String postId) async {
    lastBlockedPost = postId;
  }

  @override
  Future<void> blockCommentAuthor(String commentId) async {
    lastBlockedComment = commentId;
  }
}

BoardPost _post({
  bool canBlock = false,
  bool canReport = false,
  List<BoardComment> comments = const [],
}) => BoardPost(
  id: 'f1',
  type: BoardType.free,
  title: '자유 글',
  body: '본문',
  author: '유저',
  createdAt: DateTime(2026, 6, 23, 10),
  comments: comments,
  listCommentCount: comments.length,
  canReport: canReport,
  canBlock: canBlock,
);

BoardComment _comment({bool canBlock = false}) => BoardComment(
  id: 'c1',
  author: '유저2',
  body: '댓글 본문',
  createdAt: DateTime(2026, 6, 23, 11),
  canBlock: canBlock,
);

// 확인 다이얼로그의 '차단' 버튼(댓글 액션 '차단' 과 구분).
Finder _dialogBlock() =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text('차단'));

void main() {
  testWidgets('게시글 canBlock=true → ⋯ 메뉴에 사용자 차단 노출', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: BoardDetailScreen(
          postId: 'f1',
          repository: _BlockRepo(_post(canBlock: true)),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('사용자 차단'), findsOneWidget);
  });

  testWidgets('게시글 canBlock=false(신고만) → 사용자 차단 미노출', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: BoardDetailScreen(
          postId: 'f1',
          repository: _BlockRepo(_post(canReport: true)),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('신고'), findsOneWidget);
    expect(find.text('사용자 차단'), findsNothing);
  });

  testWidgets('사용자 차단 → 확인 → board-post 차단 호출 + pop', (t) async {
    final repo = _BlockRepo(_post(canBlock: true));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => Navigator.push(
                ctx,
                MaterialPageRoute(
                  builder: (_) =>
                      BoardDetailScreen(postId: 'f1', repository: repo),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('사용자 차단'));
    await t.pumpAndSettle(); // 확인 다이얼로그
    await t.tap(_dialogBlock());
    await t.pumpAndSettle();
    expect(repo.lastBlockedPost, 'f1'); // board-post 차단 호출
    expect(find.byType(BoardDetailScreen), findsNothing); // pop('changed')
  });

  testWidgets('차단 확인 취소 → 차단 미호출 + 화면 유지', (t) async {
    final repo = _BlockRepo(_post(canBlock: true));
    await t.pumpWidget(
      MaterialApp(
        home: BoardDetailScreen(postId: 'f1', repository: repo),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('사용자 차단'));
    await t.pumpAndSettle();
    await t.tap(find.text('취소'));
    await t.pumpAndSettle();
    expect(repo.lastBlockedPost, isNull); // 미호출
    expect(find.byType(BoardDetailScreen), findsOneWidget); // 유지
  });

  testWidgets('댓글 canBlock=true → 차단 노출 + 확인 → board-comment 차단 호출', (t) async {
    final repo = _BlockRepo(_post(comments: [_comment(canBlock: true)]));
    await t.pumpWidget(
      MaterialApp(
        home: BoardDetailScreen(postId: 'f1', repository: repo),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('차단'), findsOneWidget); // 댓글 액션 차단
    await t.tap(find.text('차단'));
    await t.pumpAndSettle();
    await t.tap(_dialogBlock());
    await t.pumpAndSettle();
    expect(repo.lastBlockedComment, 'c1');
  });
}
