import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/home_notice_banner.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 네트워크 없는 fake — fetchList 호출 인자 캡처 + 정해진 목록/오류 반환.
class _FakeRepo extends BoardRepository {
  final List<BoardPost> posts;
  final bool fail;
  String? lastSection;
  String? lastType;
  int? lastSize;
  _FakeRepo({this.posts = const [], this.fail = false});

  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    int page = 0,
    int size = 20,
  }) async {
    lastSection = section;
    lastType = type;
    lastSize = size;
    if (fail) throw Exception('network down');
    return BoardListResult(
      posts: posts,
      page: 0,
      size: size,
      totalPages: 1,
      totalElements: posts.length,
    );
  }
}

BoardPost _notice(
  String id,
  String title, {
  bool pinned = false,
  String type = 'notice',
}) => BoardPost.fromJson({
  'id': id,
  'type': type,
  'title': title,
  'body': 'b',
  'author': '운영팀',
  'createdAt': '2026-06-24T10:00:00',
  'isPinned': pinned,
});

Future<void> _pump(WidgetTester t, BoardRepository repo) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: HomeNoticeBanner(repository: repo)),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets('첫 유효 공지(서버 핀 우선 순서의 첫 항목) 표시 + official/notice 질의', (t) async {
    final repo = _FakeRepo(
      posts: [_notice('n1', '핀 공지', pinned: true), _notice('n2', '일반 공지')],
    );
    await _pump(t, repo);
    expect(find.text('핀 공지'), findsOneWidget); // 서버 순서 첫 항목
    expect(find.text('일반 공지'), findsNothing); // 배너는 첫 항목만
    expect(find.byIcon(Icons.campaign), findsOneWidget);
    expect(repo.lastSection, 'official');
    expect(repo.lastType, 'notice');
  });

  testWidgets('공지 0건 → 배너 숨김(SizedBox)', (t) async {
    await _pump(t, _FakeRepo(posts: const []));
    expect(find.byIcon(Icons.campaign), findsNothing);
    expect(find.byType(SizedBox), findsWidgets); // shrink
  });

  testWidgets('API 오류 → 배너 숨김(홈 비차단·가짜 공지 금지)', (t) async {
    await _pump(t, _FakeRepo(fail: true));
    expect(find.byIcon(Icons.campaign), findsNothing);
  });

  testWidgets('긴 제목 → overflow 없이 ellipsis(maxLines 1)', (t) async {
    final long = '아주 긴 공지 제목 ' * 30;
    await _pump(t, _FakeRepo(posts: [_notice('n1', long)]));
    // overflow 발생 시 pumpAndSettle 단계에서 FlutterError 가 터지므로, 여기 도달 = overflow 0.
    expect(find.byIcon(Icons.campaign), findsOneWidget);
    expect(find.text(long), findsOneWidget); // 전체 텍스트는 위젯에 보존(시각적으로만 ellipsis)
  });
}
