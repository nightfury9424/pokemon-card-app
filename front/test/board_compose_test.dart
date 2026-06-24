import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_compose_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

class _Repo extends BoardRepository {
  String? lastType;
  List<String>? lastUploadIds;
  @override
  Future<String> createPost(
      {required String type,
      required String title,
      required String content,
      List<String> imageUploadIds = const []}) async {
    lastType = type;
    lastUploadIds = imageUploadIds;
    return 'new-id';
  }
}

void main() {
  testWidgets('카테고리 pill 3종 + 선택 변경 → createPost 에 선택 타입 전송', (t) async {
    final repo = _Repo();
    await t.pumpWidget(
        MaterialApp(home: BoardComposeScreen(repository: repo, initialType: BoardType.free)));
    expect(find.text('자유'), findsOneWidget);
    expect(find.text('거래후기'), findsOneWidget);
    expect(find.text('사기주의'), findsOneWidget);

    await t.tap(find.text('거래후기'));
    await t.pump();
    await t.enterText(find.byType(TextField).first, '제목입니다');
    await t.enterText(find.byType(TextField).last, '본문 내용입니다');
    await t.pump();
    await t.tap(find.text('등록'));
    await t.pumpAndSettle();

    expect(repo.lastType, 'tradeReview'); // 선택한 카테고리 전송
    expect(repo.lastUploadIds, isEmpty); // 이미지 없음
  });

  testWidgets('커스텀 카운터 N/max 형식 + 기본 카운터 숨김(중복 0)', (t) async {
    await t.pumpWidget(MaterialApp(home: BoardComposeScreen(repository: _Repo())));
    await t.enterText(find.byType(TextField).first, '안녕하세요'); // 5자
    await t.pump();
    expect(find.text('5/200'), findsOneWidget); // 커스텀 1개만(기본 카운터 숨김)
  });

  testWidgets('사진 첨부 라벨 + 추가 타일 노출(0/5)', (t) async {
    await t.pumpWidget(MaterialApp(home: BoardComposeScreen(repository: _Repo())));
    expect(find.text('사진 첨부 0/5'), findsOneWidget);
    expect(find.byIcon(Icons.add_a_photo_outlined), findsOneWidget);
  });

  testWidgets('수정모드 — 타입 고정(단일 pill) + 기존 제목 표시', (t) async {
    final editing = BoardPost(
      id: 'p1',
      type: BoardType.tradeReview,
      title: '기존 제목',
      body: '기존 본문',
      author: '나',
      createdAt: DateTime(2026, 1, 1),
    );
    await t.pumpWidget(MaterialApp(home: BoardComposeScreen(repository: _Repo(), editing: editing)));
    expect(find.text('글 수정'), findsOneWidget);
    expect(find.text('거래후기'), findsOneWidget); // 고정 카테고리
    expect(find.text('자유'), findsNothing); // 다른 카테고리 선택 불가
    expect(find.widgetWithText(TextField, '기존 제목'), findsOneWidget);
  });
}
