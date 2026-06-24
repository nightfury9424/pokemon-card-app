import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/core/widgets/auth_image.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 슬라이스6 목록 썸네일 — 이미지 있는 글만 우측 썸네일(AuthImage)+장수 배지, 없는 글은 텍스트 전폭.
class _Repo extends BoardRepository {
  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    int page = 0,
    int size = 20,
  }) async {
    final posts = page > 0
        ? <BoardPost>[]
        : [
            BoardPost(
                id: '1',
                type: BoardType.free,
                title: '사진 여러 장 글',
                body: '본문',
                author: 'u',
                createdAt: DateTime(2026, 1, 1),
                thumbnailUrl: '/api/images/secure/x',
                imageCount: 3),
            BoardPost(
                id: '2',
                type: BoardType.free,
                title: '사진 없는 글',
                body: '본문',
                author: 'u',
                createdAt: DateTime(2026, 1, 1)),
          ];
    return BoardListResult(
        posts: posts, page: page, size: size, totalPages: 1, totalElements: posts.length);
  }
}

void main() {
  setUp(() {
    // AuthImage → TokenStorage(flutter_secure_storage) 플러그인 mock (MissingPluginException 회피).
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      null,
    );
  });

  testWidgets('이미지 글=우측 썸네일+장수 배지(3) / 무이미지 글=썸네일 없음, 오버플로 0', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: _Repo())));
    await t.pumpAndSettle();
    expect(find.byType(AuthImage), findsOneWidget); // 이미지 글 1개만 썸네일
    expect(find.text('3'), findsOneWidget); // 장수 배지(2장 이상)
  });
}
