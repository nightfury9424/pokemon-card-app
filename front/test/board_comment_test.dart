import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 댓글·1단 대댓글 작성·삭제 위젯 테스트. 실네트워크 없음.

class _Repo extends BoardRepository {
  final String type;
  List<BoardComment> comments;
  int createCalls = 0;
  int deleteCalls = 0;
  String? lastContent;
  String? lastParent;
  final Object? createThrows;
  final Object? deleteThrows;
  final Duration delay;
  _Repo({
    this.type = 'free',
    List<BoardComment>? comments,
    this.createThrows,
    this.deleteThrows,
    this.delay = Duration.zero,
  }) : comments = comments ?? <BoardComment>[];

  BoardType get _t => type == 'notice' ? BoardType.notice : BoardType.free;

  @override
  Future<BoardPost?> fetchDetail(String id) async => BoardPost(
        id: 'p1',
        type: _t,
        title: '제목',
        body: '본문',
        author: '글쓴이',
        createdAt: DateTime(2026, 6, 24, 10),
        likeCount: 77, // engagement row 하트수와 댓글수('0'/'1') 구분용(고정)
        comments: List.of(comments),
      );

  @override
  Future<String> createComment(String postId,
      {required String content, String? parentCommentId}) async {
    createCalls++;
    lastContent = content;
    lastParent = parentCommentId;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (createThrows != null) throw createThrows!;
    if (parentCommentId == null) {
      comments = [
        ...comments,
        BoardComment(
            id: 'new$createCalls',
            author: '나',
            body: content,
            createdAt: DateTime(2026, 6, 24, 11),
            mine: true,
            canDelete: true,
            canReply: true,
            replyTargetCommentId: 'new$createCalls'),
      ];
    }
    return 'new$createCalls';
  }

  @override
  Future<void> deleteComment(String commentId) async {
    deleteCalls++;
    if (deleteThrows != null) throw deleteThrows!;
    comments = comments.where((c) => c.id != commentId).toList();
  }
}

BoardComment _c({
  String id = 'c1',
  String author = '작성자',
  String body = '댓글내용',
  bool mine = false,
  bool canDelete = false,
  bool canReply = false,
  String? replyTarget,
  List<BoardComment> replies = const [],
}) =>
    BoardComment(
      id: id,
      author: author,
      body: body,
      createdAt: DateTime(2026, 6, 24, 10),
      mine: mine,
      canDelete: canDelete,
      canReply: canReply,
      replyTargetCommentId: replyTarget,
      replies: replies,
    );

Future<void> _pump(WidgetTester t, _Repo repo) async {
  await t.pumpWidget(MaterialApp(home: BoardDetailScreen(postId: 'p1', repository: repo)));
  await t.pumpAndSettle();
}

Finder get _input => find.byType(TextField);
Finder get _send => find.byIcon(Icons.send_rounded);

void main() {
  group('댓글 작성', () {
    testWidgets('일반 댓글 작성 성공 → create 1회·parent null·입력 초기화·댓글 수 갱신', (tester) async {
      final repo = _Repo(comments: []);
      await _pump(tester, repo);
      expect(find.text('댓글 0'), findsOneWidget); // engagement row 댓글 수
      await tester.enterText(_input, '첫 댓글');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(repo.lastContent, '첫 댓글');
      expect(repo.lastParent, isNull);
      expect(find.text('댓글 1'), findsOneWidget); // 댓글 수 갱신(engagement row)
      expect(find.text('첫 댓글'), findsOneWidget); // 목록 반영(입력은 비워짐)
    });

    testWidgets('대댓글 작성 → parent=최상위 replyTargetCommentId', (tester) async {
      final repo = _Repo(comments: [_c(id: 't1', author: '글쓴이', canReply: true, replyTarget: 't1')]);
      await _pump(tester, repo);
      await tester.tap(find.text('답글'));
      await tester.pumpAndSettle();
      expect(find.textContaining('글쓴이님에게 답글'), findsOneWidget);
      await tester.enterText(_input, '답글내용');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(repo.lastContent, '답글내용');
      expect(repo.lastParent, 't1');
    });

    testWidgets('대댓글에 답글 → 2단 금지: parent=최상위(reply 의 replyTarget)', (tester) async {
      final reply = _c(id: 'r1', author: '답글러', canReply: true, replyTarget: 't1');
      final repo = _Repo(
          comments: [_c(id: 't1', author: '글쓴이', canReply: true, replyTarget: 't1', replies: [reply])]);
      await _pump(tester, repo);
      await tester.tap(find.text('답글').last); // 대댓글의 답글
      await tester.pumpAndSettle();
      expect(find.textContaining('답글러님에게 답글'), findsOneWidget);
      await tester.enterText(_input, '재답글');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(repo.lastParent, 't1'); // 최상위 — 2단 이상 안 됨
    });

    testWidgets('답글 모드 진입·취소', (tester) async {
      final repo = _Repo(comments: [_c(id: 't1', author: '글쓴이', canReply: true, replyTarget: 't1')]);
      await _pump(tester, repo);
      await tester.tap(find.text('답글'));
      await tester.pumpAndSettle();
      expect(find.textContaining('답글 작성 중'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.textContaining('답글 작성 중'), findsNothing);
    });

    testWidgets('작성 실패 → 입력 보존·화면 유지', (tester) async {
      final repo = _Repo(comments: [], createThrows: const BoardApiException('서버 오류', statusCode: 500));
      await _pump(tester, repo);
      await tester.enterText(_input, '실패댓글');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(find.text('실패댓글'), findsOneWidget); // 입력 유지(clear 안 함)
    });

    testWidgets('대댓글 작성 실패 → 답글 모드·입력 유지', (tester) async {
      final repo = _Repo(
          comments: [_c(id: 't1', author: '글쓴이', canReply: true, replyTarget: 't1')],
          createThrows: const BoardApiException('404', statusCode: 404));
      await _pump(tester, repo);
      await tester.tap(find.text('답글'));
      await tester.pumpAndSettle();
      await tester.enterText(_input, '답글실패');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(find.textContaining('답글 작성 중'), findsOneWidget); // 답글 모드 유지
      expect(find.text('답글실패'), findsOneWidget); // 입력 유지
    });

    testWidgets('금칙어 403 → 입력 보존·화면 유지', (tester) async {
      final repo = _Repo(
          comments: [],
          createThrows: const BoardApiException('부적절한 표현이 포함되어 있어 등록할 수 없습니다.',
              code: 'CONTENT_POLICY_VIOLATION', statusCode: 403));
      await _pump(tester, repo);
      await tester.enterText(_input, '욕설댓글');
      await tester.pump();
      await tester.tap(_send);
      await tester.pumpAndSettle();
      expect(find.text('욕설댓글'), findsOneWidget);
      expect(find.byType(BoardDetailScreen), findsOneWidget);
    });

    testWidgets('전송 연타 → create 1회', (tester) async {
      final repo = _Repo(comments: [], delay: const Duration(milliseconds: 50));
      await _pump(tester, repo);
      await tester.enterText(_input, '연타댓글');
      await tester.pump();
      await tester.tap(_send);
      await tester.tap(_send); // 같은 프레임 연타
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
    });
  });

  group('댓글 삭제', () {
    testWidgets('본인 댓글 삭제 성공 → delete 1회', (tester) async {
      final repo = _Repo(comments: [_c(id: 'm1', author: '나', mine: true, canDelete: true)]);
      await _pump(tester, repo);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('댓글을 삭제할까요?'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('삭제'))); // 다이얼로그 확인
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 1);
    });

    testWidgets('본인 대댓글 삭제 성공 → delete 1회', (tester) async {
      final reply = _c(id: 'mr1', author: '나', mine: true, canDelete: true);
      final repo = _Repo(comments: [_c(id: 't1', author: '글쓴이', replies: [reply])]);
      await _pump(tester, repo);
      await tester.tap(find.text('삭제')); // 대댓글의 삭제(유일)
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('삭제')));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 1);
    });

    testWidgets('삭제 취소 → delete 미호출', (tester) async {
      final repo = _Repo(comments: [_c(id: 'm1', author: '나', mine: true, canDelete: true)]);
      await _pump(tester, repo);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('취소')));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 0);
    });

    testWidgets('삭제 실패 → delete 1회·화면 유지·재시도 가능', (tester) async {
      final repo = _Repo(
          comments: [_c(id: 'm1', author: '나', body: '내댓글', mine: true, canDelete: true)],
          deleteThrows: const BoardApiException('서버 오류', statusCode: 500));
      await _pump(tester, repo);
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('삭제')));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 1);
      expect(find.text('내댓글'), findsOneWidget); // 유지
      // 재시도
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('삭제')));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 2);
    });

    testWidgets('타인 댓글 → 삭제 버튼 미노출', (tester) async {
      final repo = _Repo(comments: [_c(id: 'o1', author: '남', mine: false, canDelete: false, canReply: true, replyTarget: 'o1')]);
      await _pump(tester, repo);
      expect(find.text('삭제'), findsNothing);
      expect(find.text('답글'), findsOneWidget); // 답글은 노출
    });
  });

  group('노출 제어', () {
    testWidgets('canReply=false → 답글 버튼 미노출', (tester) async {
      final repo = _Repo(comments: [_c(id: 'c1', canReply: false, canDelete: true, mine: true)]);
      await _pump(tester, repo);
      expect(find.text('답글'), findsNothing);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('공지 상세 → 댓글 입력창·입력 노출(1.0.4 공식글 engagement)', (tester) async {
      final repo = _Repo(type: 'notice', comments: []);
      await _pump(tester, repo);
      expect(find.byType(TextField), findsOneWidget); // ★공식글도 입력창 노출
      expect(find.text('댓글을 입력하세요'), findsOneWidget);
    });
  });

  group('반응형', () {
    final longName = '가나다라마바사아자차카타파하갸'; // 긴 닉네임
    for (final size in const [Size(320, 568), Size(375, 667), Size(430, 932)]) {
      for (final scale in const [1.0, 1.3, 1.6]) {
        testWidgets('overflow 0 — ${size.width.toInt()}x${size.height.toInt()} @x$scale + 키보드/긴닉/대댓글',
            (tester) async {
          tester.view.devicePixelRatio = 3.0;
          tester.view.physicalSize = size * 3.0;
          addTearDown(tester.view.reset);
          final repo = _Repo(comments: [
            _c(
                id: 't1',
                author: longName,
                body: '긴 댓글 본문 ' * 5,
                mine: true,
                canDelete: true,
                canReply: true,
                replyTarget: 't1',
                replies: [_c(id: 'r1', author: longName, body: '대댓글 본문 ' * 3, canReply: true, replyTarget: 't1')]),
          ]);
          await tester.pumpWidget(MaterialApp(
            home: Builder(
              builder: (ctx) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 300),
                  padding: const EdgeInsets.only(top: 47, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
                ),
                child: BoardDetailScreen(postId: 'p1', repository: repo),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
