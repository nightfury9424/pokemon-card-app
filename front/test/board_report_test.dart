import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 게시판 신고 진입점 — 서버 canReport 플래그 게이팅 + 공용 ReportSheet 연결(게시글/댓글) 검증.
class _FakeDetail extends BoardRepository {
  final BoardPost post;
  const _FakeDetail(this.post);
  @override
  Future<BoardPost?> fetchDetail(String id) async => post;
}

BoardPost _post({
  bool canReport = false,
  bool canEdit = false,
  bool canDelete = false,
  bool canBlock = false,
  List<BoardComment> comments = const [],
}) => BoardPost(
  id: 'f1',
  type: BoardType.free,
  title: '자유 글',
  body: '본문',
  author: '유저',
  createdAt: DateTime(2026, 6, 23, 10),
  viewCount: 5,
  comments: comments,
  listCommentCount: comments.length,
  canEdit: canEdit,
  canDelete: canDelete,
  canReport: canReport,
  canBlock: canBlock,
);

BoardComment _comment({bool canReport = false, bool canDelete = false}) =>
    BoardComment(
      id: 'c1',
      author: '유저2',
      body: '댓글 본문',
      createdAt: DateTime(2026, 6, 23, 11),
      canReport: canReport,
      canDelete: canDelete,
    );

Future<void> _pump(WidgetTester t, BoardPost post) async {
  await t.pumpWidget(
    MaterialApp(
      home: BoardDetailScreen(postId: 'f1', repository: _FakeDetail(post)),
    ),
  );
  await t.pumpAndSettle();
}

// 게시글 신고 시트 열기(키 큰 화면 = 시트 위 배리어 영역 확보).
Future<void> _openSheet(WidgetTester t) async {
  t.view.physicalSize = const Size(1000, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await _pump(t, _post(canReport: true));
  await t.tap(find.byIcon(Icons.more_vert));
  await t.pumpAndSettle();
  await t.tap(find.text('신고하기'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('공식글/비본인(canReport, 차단·수정·삭제 불가) → 신고하기만 노출', (t) async {
    await _pump(t, _post(canReport: true)); // canEdit/canDelete/canBlock=false = 공식글 일반사용자 시점
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget);
    expect(find.text('수정'), findsNothing);
    expect(find.text('삭제'), findsNothing);
    expect(find.text('사용자 차단'), findsNothing); // 공식(운영팀) 차단 불가
  });

  testWidgets('본인 글(canEdit/canDelete) → 수정/삭제만, 신고 미노출', (t) async {
    await _pump(
      t,
      _post(canEdit: true, canDelete: true),
    ); // canReport=false(본인)
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    expect(find.text('수정'), findsOneWidget);
    expect(find.text('삭제'), findsOneWidget);
    expect(find.text('신고하기'), findsNothing);
  });

  testWidgets('플래그 모두 false(공식/본문만) → ⋯ 메뉴 자체 미노출', (t) async {
    await _pump(t, _post());
    expect(find.byIcon(Icons.more_vert), findsNothing);
  });

  testWidgets('다른 사용자 글 신고 탭 → 게시글 대상 ReportSheet(autoBlock, board 사유, ABUSIVE_PRICE 제외)', (
    t,
  ) async {
    await _pump(t, _post(canReport: true, canBlock: true)); // 커뮤니티 비본인 → autoBlock
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('신고하기'));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget); // ReportSheet 제목
    expect(find.text('욕설 / 비방'), findsOneWidget); // board 사유
    expect(find.text('시세 교란'), findsNothing); // ABUSIVE_PRICE 제외
    expect(find.textContaining('게시글'), findsWidgets); // autoBlock 경고 targetNoun
  });

  testWidgets('공식글 신고(canBlock=false) → autoBlock 경고 없음(운영팀 차단 안 함)', (t) async {
    await _pump(t, _post(canReport: true)); // canBlock=false = 공식글 일반사용자 시점
    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();
    await t.tap(find.text('신고하기'));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget); // 시트는 열림
    expect(find.textContaining('게시글'), findsNothing); // ★autoBlock 경고(targetNoun) 미노출
  });

  testWidgets('댓글 canReport=true → 신고 노출 + 탭 시 댓글 대상 ReportSheet', (t) async {
    await _pump(t, _post(comments: [_comment(canReport: true)]));
    expect(find.text('신고'), findsOneWidget); // 댓글 액션(게시글 ⋯ 메뉴는 미노출)
    await t.tap(find.text('신고'));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget);
    expect(find.textContaining('댓글'), findsWidgets); // targetNoun='댓글'
  });

  testWidgets('댓글 canReport=false → 신고 미노출', (t) async {
    await _pump(t, _post(comments: [_comment()]));
    expect(find.text('신고'), findsNothing);
  });

  testWidgets('ReportSheet 배경 탭 → 시트 유지(isDismissible:false)', (t) async {
    await _openSheet(t);
    expect(find.text('신고하기'), findsOneWidget);
    await t.tapAt(const Offset(500, 30)); // 시트 위 배리어 영역
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget); // 배경 탭으로 닫히지 않음
  });

  testWidgets('ReportSheet 아래로 드래그 → 시트 유지(enableDrag:false)', (t) async {
    await _openSheet(t);
    await t.drag(find.text('신고하기'), const Offset(0, 600));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsOneWidget); // 드래그로 닫히지 않음
  });

  testWidgets('ReportSheet 닫기(X) 버튼(제출 전) → 닫힘', (t) async {
    await _openSheet(t);
    expect(find.text('신고하기'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.text('신고하기'), findsNothing); // 명시적 닫기는 동작
  });

  testWidgets('ReportSheet 는 PopScope(canPop:!submitting) 로 감싸짐(시스템 뒤로 가드)', (
    t,
  ) async {
    await _openSheet(t);
    expect(
      find.ancestor(of: find.text('신고하기'), matching: find.byType(PopScope)),
      findsOneWidget,
    );
  });

  // ★기타(OTHER) 사유 직접입력 필수 — 빈칸이면 제출 비활성, 입력하면 활성.
  testWidgets('기타 사유: 빈 detail → 제출 비활성 / 입력 시 활성', (t) async {
    await _openSheet(t);
    await t.tap(find.text('기타'));
    await t.pumpAndSettle();
    final detail = find.byKey(const Key('report_detail_field')); // 시트 상세입력(고유 키)
    expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '신고 접수')).onPressed,
        isNull); // 빈칸 → 비활성
    await t.enterText(detail, '직접 사유');
    await t.pump();
    expect(t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, '신고 접수')).onPressed,
        isNotNull); // 입력 → 활성
  });

  // ★기타에 입력 후 다른 사유로 바꾸면 직접사유가 잔류·오전송되지 않게 clear.
  testWidgets('기타 입력 후 다른 사유로 변경 → 직접사유 잔류 제거', (t) async {
    await _openSheet(t);
    await t.tap(find.text('기타'));
    await t.pumpAndSettle();
    final detail = find.byKey(const Key('report_detail_field'));
    await t.enterText(detail, '직접 사유 입력');
    await t.pump();
    expect(t.widget<TextField>(detail).controller!.text, '직접 사유 입력');
    await t.tap(find.text('스팸 / 광고')); // 다른 사유 선택
    await t.pumpAndSettle();
    expect(t.widget<TextField>(detail).controller!.text, isEmpty); // ★잔류 detail 제거(오전송 방지)
  });
}
