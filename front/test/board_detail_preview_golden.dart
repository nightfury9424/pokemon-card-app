// 일회성 — 게시글 상세 NEW 레이아웃 프리뷰(제목→본문→작성자메타→좋아요/댓글→댓글).
// 실행: flutter test test/board_detail_preview_golden.dart --update-goldens
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

class _DetailRepo extends BoardRepository {
  final BoardPost post;
  _DetailRepo(this.post);
  @override
  Future<BoardPost?> fetchDetail(String id) async => post;
  @override
  Future<int?> recordView(String id) async => null;
}

BoardPost _post({
  required String title,
  required String body,
  required String author,
  int comments = 2,
}) =>
    BoardPost(
      id: 'd',
      type: BoardType.free,
      title: title,
      body: body,
      author: author,
      createdAt: DateTime(2026, 6, 27, 14),
      likeCount: 1,
      viewCount: 2,
      listCommentCount: comments,
      comments: comments == 0
          ? const []
          : [
              BoardComment(id: 'c1', author: 'iian', body: '댓', createdAt: DateTime(2026, 6, 27, 3)),
              BoardComment(id: 'c2', author: 'iian', body: 'ww', createdAt: DateTime(2026, 6, 27, 3)),
            ],
    );

Future<void> _loadFont() async {
  final bytes = File('/System/Library/Fonts/Supplemental/AppleGothic.ttf').readAsBytesSync();
  await (FontLoader('AppleGothic')
        ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer))))
      .load();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await _loadFont();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async => null);
  });

  ThemeData theme() => ThemeData(
        fontFamily: 'AppleGothic',
        scaffoldBackgroundColor: const Color(0xFF070C12),
        useMaterial3: true,
      );

  Future<void> render(WidgetTester t, BoardPost post, Size size, String file) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = size * 2.0;
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(MaterialApp(
        theme: theme(),
        home: BoardDetailScreen(postId: 'd', repository: _DetailRepo(post), summary: post)));
    await t.pumpAndSettle();
    await expectLater(find.byType(BoardDetailScreen), matchesGoldenFile(file));
  }

  testWidgets('detail 기본 small (375x667) — 짧은 본문 + 댓글 2', (t) async {
    await render(t, _post(title: 's', body: 'ss', author: 'kjx'),
        const Size(375, 667), 'detail_small.png');
  });

  testWidgets('detail 기본 large (430x932)', (t) async {
    await render(t, _post(title: 's', body: 'ss', author: 'kjx'),
        const Size(430, 932), 'detail_large.png');
  });

  testWidgets('detail 긴 제목/긴 본문 (430x932)', (t) async {
    await render(
        t,
        _post(
            title: '리자몽 ex SAR 시세 요즘 어떻게 보세요? 의견 궁금합니다',
            body: '요즘 좀 오른 것 같은데 다들 어떠세요?\n특히 SAR 시세가 궁금하네요. '
                '박스 깐 거 인증도 같이 올려봅니다. 다들 어디서 거래하시는지도 알려주시면 감사하겠습니다.',
            author: '닉네임길게쓰는유저입니다'),
        const Size(430, 932),
        'detail_long.png');
  });

  testWidgets('detail 댓글 0개 (375x667)', (t) async {
    await render(t, _post(title: '질문 있어요', body: '짧은 본문 한 줄', author: 'nightfury', comments: 0),
        const Size(375, 667), 'detail_empty.png');
  });
}
