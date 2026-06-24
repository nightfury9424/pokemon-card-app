import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/widgets/auth_image.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 상세 읽기 연결 검증 — postId 재조회 / 공지=본문만 / 자유=댓글트리 / 404 / 오류.
class _FakeDetail extends BoardRepository {
  final BoardPost? post;
  final bool error;
  const _FakeDetail({this.post, this.error = false});
  @override
  Future<BoardPost?> fetchDetail(String id) async {
    if (error) throw const BoardParseException('parse');
    return post;
  }
}

BoardPost _free() => BoardPost(
      id: 'f1',
      type: BoardType.free,
      title: '자유 글 제목',
      body: '자유 본문',
      author: '유저',
      createdAt: DateTime(2026, 6, 23, 10),
      viewCount: 5,
      likeCount: 0,
      comments: [
        BoardComment(
            id: 'c1',
            author: '운영팀',
            body: '첫 댓글',
            createdAt: DateTime(2026, 6, 23, 11),
            isAdmin: true,
            replies: [
              BoardComment(
                  id: 'r1',
                  author: '유저2',
                  body: '답글',
                  createdAt: DateTime(2026, 6, 23, 12)),
            ]),
      ],
      listCommentCount: 2,
    );

BoardPost _official() => BoardPost(
      id: 'n1',
      type: BoardType.notice,
      title: '공지 제목',
      body: '공지 본문',
      author: '운영팀',
      createdAt: DateTime(2026, 6, 23, 9),
      viewCount: 0,
    );

Future<void> _pump(WidgetTester t, BoardRepository repo, BoardPost? summary) async {
  await t.pumpWidget(MaterialApp(
      home: BoardDetailScreen(postId: 'x', repository: repo, summary: summary)));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    // AuthImage → TokenStorage(flutter_secure_storage) 플러그인 mock (갤러리 렌더용).
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  testWidgets('이미지 글 → 본문 아래 갤러리 2장 + 탭→전체화면 뷰어', (tester) async {
    final post = BoardPost(
      id: 'f1',
      type: BoardType.free,
      title: '제목',
      body: '본문',
      author: 'u',
      createdAt: DateTime(2026, 1, 1),
      images: const [
        BoardPostImage(imageId: 'i1', url: '/api/images/secure/a', sortOrder: 0),
        BoardPostImage(imageId: 'i2', url: '/api/images/secure/b', sortOrder: 1),
      ],
    );
    await _pump(tester, _FakeDetail(post: post), post);
    expect(find.byType(AuthImage), findsNWidgets(2)); // 본문 아래 갤러리 2장
    await tester.tap(find.byType(AuthImage).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget); // 전체화면 뷰어 열림
    expect(find.text('1 / 2'), findsOneWidget); // 페이지 표시
  });

  testWidgets('자유 상세 — 본문 + 댓글트리 표시', (tester) async {
    await _pump(tester, _FakeDetail(post: _free()), _free());
    expect(tester.takeException(), isNull);
    expect(find.text('자유 본문'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // 댓글 수(engagement row, listCommentCount=2)
    expect(find.text('첫 댓글'), findsOneWidget);
    expect(find.text('답글'), findsOneWidget); // 1단 대댓글
    expect(find.text('댓글을 입력하세요'), findsOneWidget); // 자유는 입력바 노출
  });

  testWidgets('공지 상세 — 본문 + 댓글·입력바 노출(1.0.4 공식글 engagement)', (tester) async {
    await _pump(tester, _FakeDetail(post: _official()), _official());
    expect(tester.takeException(), isNull);
    expect(find.text('공지 본문'), findsOneWidget);
    expect(find.text('댓글을 입력하세요'), findsOneWidget); // ★공식글도 입력바 노출
    expect(find.text('아직 댓글이 없어요'), findsOneWidget); // 댓글 섹션 노출
    expect(find.textContaining('조회'), findsNothing); // viewCount 0 → 숨김
  });

  testWidgets('404 — 삭제/숨김/미존재 안내', (tester) async {
    await _pump(tester, const _FakeDetail(post: null), _official());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('삭제되었거나'), findsOneWidget);
  });

  testWidgets('오류 — 메시지 + 다시 시도', (tester) async {
    await _pump(tester, const _FakeDetail(error: true), _official());
    expect(tester.takeException(), isNull);
    expect(find.textContaining('불러오지 못'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('빈 author 크래시 가드 — 이니셜 ? 렌더', (tester) async {
    final p = BoardPost(
        id: 'e1',
        type: BoardType.free,
        title: 't',
        body: 'b',
        author: '', // 빈 author
        createdAt: DateTime(2026, 6, 23, 10));
    await _pump(tester, _FakeDetail(post: p), p);
    expect(tester.takeException(), isNull); // .characters.first throw 안 함
  });
}
