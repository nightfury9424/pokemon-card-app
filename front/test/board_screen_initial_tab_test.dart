import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_filter.dart';

/// fetchList 호출 인자(section/type)를 기록하는 fake — initialFilter·탭전환·FAB 검증용.
class _RecordRepo extends BoardRepository {
  String? lastSection;
  String? lastType;
  _RecordRepo();

  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    int page = 0,
    int size = 20,
  }) async {
    lastSection = section;
    lastType = type;
    return BoardListResult(
      posts: const [],
      page: 0,
      size: size,
      totalPages: 0,
      totalElements: 0,
    );
  }
}

void main() {
  testWidgets('initialFilter.notice → type=notice 로 진입(section 미사용)', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(
      MaterialApp(home: BoardScreen(initialFilter: BoardFilter.notice, repository: repo)),
    );
    await t.pumpAndSettle();
    expect(repo.lastSection, isNull);
    expect(repo.lastType, 'notice');
    expect(find.text('등록된 공지 게시글이 없어요'), findsOneWidget);
  });

  testWidgets('기본(미지정) → 전체(type=null) + 7탭 라벨 노출', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    expect(repo.lastSection, isNull);
    expect(repo.lastType, isNull); // 전체=미필터
    for (final f in BoardFilter.values) {
      expect(find.text(f.label), findsWidgets); // 전체|공지|이벤트|패치노트|자유|거래후기|사기주의
    }
  });

  testWidgets('탭 전환: 거래후기 → type=tradeReview', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    await t.tap(find.text('거래후기'));
    await t.pumpAndSettle();
    expect(repo.lastType, 'tradeReview');
  });

  testWidgets('FAB — 전체=노출, 공지(공식)=미노출', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo))); // 전체
    await t.pumpAndSettle();
    expect(find.text('글쓰기'), findsOneWidget);
    await t.tap(find.text('공지'));
    await t.pumpAndSettle();
    expect(find.text('글쓰기'), findsNothing); // 공식 카테고리=앱 작성 불가
  });
}
