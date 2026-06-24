import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 게시판 신고 진입점 — 서버 canReport 플래그 게이팅 + 공용 ReportSheet 연결(게시글/댓글) 검증.
class _FakeDetail extends BoardRepository {
  final BoardPost post;
  const _FakeDetail(this.post);
  @override
  Future<BoardPost?> fetchDetail(String id) async => post;
}

BoardPost _post({
  bool canReport = false,
  bool canEdit = false,
  bool canDelete = false,
  List<BoardComment> comments = const [],
}) => BoardPost(
  id: 'f1',
  type: BoardType.free,
  title: '자유 글',
  body: '본문',
  author: '유저',
  createdAt: DateTime(2026, 6, 23, 10),
  viewCount: 5,
  comments: comments,
  listCommentCount: comments.length,
  canEdit: canEdit,
  canDelete: canDelete,
  canReport: canReport,
);

BoardComment _comment({bool canReport = false, bool canDelete = false}) =>
    BoardComment(
      id: 'c1',
      author: '유저2',
      body: '댓글 본문',
      createdAt: DateTime(2026, 6, 23, 11),
      canReport: canReport,
      canDelete: canDelete,
    );

Future<void> _pump(WidgetTester t, BoardPost post) async {
  await t.pumpWidget(
    MaterialApp(
      home: BoardDetailScreen(postId: 'f1', repository: _FakeDetail(post)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('게시글 canReport=true → ⋯ 메뉴에 신고 노출(비본인=수정/삭제 없음)', (t) async {
    await _pump(t, _post(canReport: true));
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('신고'), findsOneWidget);
    expect(find.text('수정'), findsNothing);
    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('본인 글(canEdit/canDelete) → 수정/삭제만, 신고 미노출', (t) async {
    await _pump(
      t,
      _post(canEdit: true, canDelete: true),
    ); // canReport=false(본인)
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('수정'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
    expect(find.text('신고'), findsNothing);
  });

  testWidgets('플래그 모두 false(공식/본문만) → ⋯ 메뉴 자체 미노출', (t) async {
    await _pump(t, _post());
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('게시글 신고 탭 → 게시글 대상 ReportSheet(board 사유, ABUSIVE_PRICE 제외)', (
    t,
  ) async {
    await _pump(t, _post(canReport: true));
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('신고'));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget); // ReportSheet 제목
    expect(find.text('욕설 / 비방'), findsOneWidget); // board 사유
    expect(find.text('시세 교란'), findsNothing); // ABUSIVE_PRICE 제외
    expect(find.textContaining('게시글'), findsWidgets); // autoBlock 경고 targetNoun
  });

  testWidgets('댓글 canReport=true → 신고 노출 + 탭 시 댓글 대상 ReportSheet', (t) async {
    await _pump(t, _post(comments: [_comment(canReport: true)]));
    expect(find.text('신고'), findsOneWidget); // 댓글 액션(게시글 ⋯ 메뉴는 미노출)
    await t.tap(find.text('신고'));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget);
    expect(find.textContaining('댓글'), findsWidgets); // targetNoun='댓글'
  });

  testWidgets('댓글 canReport=false → 신고 미노출', (t) async {
    await _pump(t, _post(comments: [_comment()]));
    expect(find.text('신고'), findsNothing);
  });
}
