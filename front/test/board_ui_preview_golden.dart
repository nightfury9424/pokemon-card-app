// 일회성 UI 프리뷰 골든 — 실제 위젯을 AppleGothic(한글) 폰트로 렌더해 PNG 추출.
// 실행: flutter test test/board_ui_preview_golden.dart --update-goldens  → test/preview_*.png 생성.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

class _ListRepo extends BoardRepository {
  @override
  Future<BoardListResult> fetchList({
    String? section, String? type, String? q,
    bool pinnedOnly = false, int page = 0, int size = 20,
  }) async {
    final posts = page > 0 ? <BoardPost>[] : [
      BoardPost(id: '1', type: BoardType.free, title: 'ㅎㅇ', body: 'ㅎㅇ',
          author: 'nightfury', createdAt: DateTime(2026, 6, 27, 3),
          likeCount: 0, viewCount: 0, listCommentCount: 0),
      BoardPost(id: '2', type: BoardType.free, title: '게시판 Test', body: 'ttest',
          author: 'kjx', createdAt: DateTime(2026, 6, 26, 22),
          likeCount: 1, viewCount: 0, listCommentCount: 2),
      BoardPost(id: '3', type: BoardType.free, title: 'pp', body: '사진',
          author: '팽도리', createdAt: DateTime(2026, 6, 26),
          likeCount: 1, viewCount: 1, listCommentCount: 0),
      BoardPost(id: '4', type: BoardType.notice, title: '2ㅂ2ㅂ2ㅂ', body: 'ㅂ2ㅂ2ㅂ2ㅂ2ㅂ',
          author: '운영팀', createdAt: DateTime(2026, 6, 26),
          likeCount: 0, viewCount: 0, listCommentCount: 0),
      BoardPost(id: '5', type: BoardType.free, title: '리자몽 ex 시세 어떻게 보세요?',
          body: '요즘 좀 오른 것 같은데 다들 어떠세요? 의견 궁금합니다.',
          author: 'nightfury', createdAt: DateTime(2026, 6, 25),
          likeCount: 0, viewCount: 73, listCommentCount: 0),
    ];
    return BoardListResult(posts: posts, page: page, size: size, totalPages: 1, totalElements: posts.length);
  }
}

class _DetailRepo extends BoardRepository {
  @override
  Future<BoardPost?> fetchDetail(String id) async => BoardPost(
        id: 'd1', type: BoardType.free, title: '리자몽 ex 시세 어떻게 보세요?',
        body: '요즘 좀 오른 것 같은데 다들 어떠세요? 의견 궁금합니다.\n특히 SAR 시세가 궁금하네요.',
        author: 'nightfury', createdAt: DateTime(2026, 6, 27, 5),
        likeCount: 3, viewCount: 73, listCommentCount: 2,
        comments: [
          BoardComment(id: 'c1', author: 'kjx', body: '저도 오른 것 같아요 ㅎㅎ',
              createdAt: DateTime(2026, 6, 27, 6),
              replies: [BoardComment(id: 'r1', author: '팽도리', body: '맞아요 SAR은 더 오름',
                  createdAt: DateTime(2026, 6, 27, 6, 30))]),
        ],
      );
}

Future<void> _loadFont() async {
  final bytes = File('/System/Library/Fonts/Supplemental/AppleGothic.ttf').readAsBytesSync();
  final loader = FontLoader('AppleGothic')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
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

  testWidgets('preview LIST', (t) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(786, 1704);
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(MaterialApp(theme: theme(), home: BoardScreen(repository: _ListRepo())));
    await t.pumpAndSettle();
    await expectLater(find.byType(BoardScreen), matchesGoldenFile('preview_list.png'));
  });

  testWidgets('preview DETAIL', (t) async {
    t.view.devicePixelRatio = 2.0;
    t.view.physicalSize = const Size(786, 1704);
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(MaterialApp(theme: theme(),
        home: BoardDetailScreen(postId: 'd1', repository: _DetailRepo())));
    await t.pumpAndSettle();
    await expectLater(find.byType(BoardDetailScreen), matchesGoldenFile('preview_detail.png'));
  });
}
