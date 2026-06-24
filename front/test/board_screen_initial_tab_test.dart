import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/data/board_repository.dart';

/// fetchList 호출 인자(section/type)를 기록하는 fake — initialTab → 진입 탭 검증용.
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
  testWidgets('initialTab 0 → 공지(official) 탭으로 진입', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(
      MaterialApp(home: BoardScreen(initialTab: 0, repository: repo)),
    );
    await t.pumpAndSettle();
    expect(repo.lastSection, 'official'); // 공지 탭 = section=official
    expect(repo.lastType, isNull);
    expect(find.text('등록된 공지가 없어요'), findsOneWidget); // 공지 탭 빈 상태
  });

  testWidgets('기본(initialTab 미지정) → 자유(free) 탭', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    expect(repo.lastSection, isNull);
    expect(repo.lastType, 'free');
  });
}
