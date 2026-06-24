import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_filter.dart';

/// fetchList 호출 인자(section/type)를 기록하는 fake — initialFilter·탭전환·FAB 검증용.
class _RecordRepo extends BoardRepository {
  String? lastSection;
  String? lastType;
  String? lastQ;
  int fetchCount = 0;
  _RecordRepo();

  @override
  Future<BoardListResult> fetchList({
    String? section,
    String? type,
    String? q,
    bool pinnedOnly = false,
    int page = 0,
    int size = 20,
  }) async {
    lastSection = section;
    lastType = type;
    lastQ = q;
    if (page == 0) fetchCount++;
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
  testWidgets('initialFilter.notice → section=official 로 진입(공지/이벤트/패치 통합)', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(
      MaterialApp(home: BoardScreen(initialFilter: BoardFilter.notice, repository: repo)),
    );
    await t.pumpAndSettle();
    expect(repo.lastSection, 'official');
    expect(repo.lastType, isNull);
    expect(find.text('등록된 공지 게시글이 없어요'), findsOneWidget);
  });

  testWidgets('기본(미지정) → 전체(type=null) + 3탭(전체/공지/자유)만 노출', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    expect(repo.lastSection, isNull);
    expect(repo.lastType, isNull); // 전체=미필터
    expect(BoardFilter.values.length, 3);
    for (final f in BoardFilter.values) {
      expect(find.text(f.label), findsWidgets); // 전체|공지|자유
    }
    // ★폐기된 탭 라벨은 노출 안 됨
    for (final gone in ['이벤트', '패치노트', '거래후기', '사기주의']) {
      expect(find.text(gone), findsNothing);
    }
  });

  testWidgets('탭 전환: 자유 → type=free / 공지 → section=official', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    await t.tap(find.text('자유'));
    await t.pumpAndSettle();
    expect(repo.lastType, 'free');
    expect(repo.lastSection, isNull);
    await t.tap(find.text('공지'));
    await t.pumpAndSettle();
    expect(repo.lastSection, 'official'); // 공지=official 통합
    expect(repo.lastType, isNull);
  });

  testWidgets('앱 resume → 목록 재조회(관리자 핀 변경 최신화)', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    final before = repo.fetchCount; // 초기 로드 1
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(repo.fetchCount, greaterThan(before)); // resume 시 page0 재조회
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

  testWidgets('검색 — 아이콘 탭 → 입력창 + 제목 q 전달(debounce) / clear 시 q 제거·복원', (t) async {
    final repo = _RecordRepo();
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    expect(repo.lastQ, isNull); // 초기엔 검색 없음

    await t.tap(find.byIcon(Icons.search));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget); // 입력창 노출

    await t.enterText(find.byType(TextField), '  리자몽  '); // 공백 포함
    await t.pump(const Duration(milliseconds: 350)); // debounce 경과
    await t.pumpAndSettle();
    expect(repo.lastQ, '리자몽'); // trim 후 제목 검색어 전달

    await t.tap(find.byIcon(Icons.clear)); // clear → 원래 목록 복원
    await t.pumpAndSettle();
    expect(repo.lastQ, isNull);
  });

  testWidgets('탭바 — 3탭이어도 왼쪽 정렬·전체폭(가운데 안 모임)', (t) async {
    final repo = _RecordRepo();
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1.0;
    addTearDown(() => t.view.resetPhysicalSize());
    await t.pumpWidget(MaterialApp(home: BoardScreen(repository: repo)));
    await t.pumpAndSettle();
    // 첫 탭(전체)은 왼쪽 끝 근처(13 패딩+α). 가운데 모이면 100+ 라 실패.
    expect(t.getTopLeft(find.text('전체')).dx, lessThan(40));
  });
}
