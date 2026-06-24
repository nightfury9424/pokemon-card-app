import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_compose_screen.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 자유글 작성·수정·삭제 위젯 테스트 (UI 동작 + repository 계약). 실네트워크 없음.

class _FakeWriteRepo extends BoardRepository {
  int createCalls = 0;
  int updateCalls = 0;
  int deleteCalls = 0;
  String? lastTitle;
  String? lastBody;
  final Object? throwOnSubmit;
  final Duration delay;
  _FakeWriteRepo({this.throwOnSubmit, this.delay = Duration.zero});

  @override
  Future<String> createPost(
      {required String type,
      required String title,
      required String content,
      List<String> imageUploadIds = const []}) async {
    createCalls++;
    lastTitle = title;
    lastBody = content;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throwOnSubmit != null) throw throwOnSubmit!;
    return 'new-id';
  }

  @override
  Future<void> updatePost(String postId,
      {required String title,
      required String content,
      List<Map<String, String>>? images}) async {
    updateCalls++;
    lastTitle = title;
    lastBody = content;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (throwOnSubmit != null) throw throwOnSubmit!;
  }
}

class _FakeDetailRepo extends BoardRepository {
  final BoardPost post;
  int deleteCalls = 0;
  final Object? deleteThrows;
  _FakeDetailRepo(this.post, {this.deleteThrows});

  @override
  Future<BoardPost?> fetchDetail(String id) async => post;

  @override
  Future<void> deletePost(String postId) async {
    deleteCalls++;
    if (deleteThrows != null) throw deleteThrows!;
  }
}

BoardPost _post({
  String id = 'p1',
  BoardType type = BoardType.free,
  String title = '제목',
  String body = '본문',
  bool canEdit = false,
  bool canDelete = false,
}) =>
    BoardPost(
      id: id,
      type: type,
      title: title,
      body: body,
      author: '글쓴이',
      createdAt: DateTime(2026, 6, 24, 10),
      canEdit: canEdit,
      canDelete: canDelete,
    );

Future<void> _openCompose(WidgetTester t, BoardRepository repo, List<dynamic> captured,
    {BoardPost? editing}) async {
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () async => captured.add(await Navigator.of(ctx).push(
                MaterialPageRoute(
                    builder: (_) => BoardComposeScreen(repository: repo, editing: editing)))),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String title, String body) async {
  await t.enterText(find.byType(TextField).at(0), title);
  await t.enterText(find.byType(TextField).at(1), body);
  await t.pump();
}

void main() {
  group('작성', () {
    testWidgets('성공 → postId 반환 + create 1회 + 화면 닫힘', (tester) async {
      final repo = _FakeWriteRepo();
      final captured = <dynamic>[];
      await _openCompose(tester, repo, captured);
      await _type(tester, '제목입니다', '본문입니다');
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(repo.lastTitle, '제목입니다');
      expect(repo.lastBody, '본문입니다');
      expect(captured, ['new-id']); // 성공 시 postId pop
    });

    testWidgets('빈 입력이면 등록 비활성(미호출)', (tester) async {
      final repo = _FakeWriteRepo();
      await _openCompose(tester, repo, <dynamic>[]);
      await _type(tester, '제목만', ''); // 본문 비어있음
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
      expect(repo.createCalls, 0);
    });

    testWidgets('일반 실패 → 입력 보존 + 화면 유지(미pop)', (tester) async {
      final repo = _FakeWriteRepo(throwOnSubmit: const BoardApiException('서버 오류', statusCode: 500));
      final captured = <dynamic>[];
      await _openCompose(tester, repo, captured);
      await _type(tester, '제목입니다', '본문입니다');
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(captured, isEmpty); // pop 안 됨
      expect(find.text('제목입니다'), findsOneWidget); // 입력 보존
      expect(find.text('본문입니다'), findsOneWidget);
    });

    testWidgets('금칙어 403 → 입력 보존 + 화면 유지', (tester) async {
      final repo = _FakeWriteRepo(
          throwOnSubmit: const BoardApiException('부적절한 표현이 포함되어 있어 등록할 수 없습니다.',
              code: 'CONTENT_POLICY_VIOLATION', statusCode: 403));
      final captured = <dynamic>[];
      await _openCompose(tester, repo, captured);
      await _type(tester, '욕설제목', '욕설본문');
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
      expect(captured, isEmpty);
      expect(find.text('욕설제목'), findsOneWidget);
      expect(find.text('욕설본문'), findsOneWidget);
    });

    testWidgets('금칙어 403 후 포커스·키보드 유지 + 키보드 inset overflow 0', (tester) async {
      final repo = _FakeWriteRepo(
          throwOnSubmit: const BoardApiException('부적절한 표현이 포함되어 있어 등록할 수 없습니다.',
              code: 'CONTENT_POLICY_VIOLATION', statusCode: 403));
      // 키보드 열린 상태(viewInsets) 가정 + 직접 pump(포커스/키보드 상태 검사용).
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
            child: BoardComposeScreen(repository: repo),
          ),
        ),
      ));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), '욕설제목');
      await tester.enterText(find.byType(TextField).at(1), '욕설본문'); // 본문 포커스
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue); // 제출 전 키보드 연결
      await tester.tap(find.text('등록'));
      await tester.pumpAndSettle();
      // 입력·화면 유지
      expect(find.text('욕설제목'), findsOneWidget);
      expect(find.text('욕설본문'), findsOneWidget);
      expect(find.byType(BoardComposeScreen), findsOneWidget);
      // ★unfocus 안 함 → 키보드/포커스 유지(텍스트 입력 연결 유지). 실제 OS 키보드 표시는 위젯테스트 한계.
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.binding.focusManager.primaryFocus, isNotNull);
      expect(tester.takeException(), isNull); // viewInsets(키보드)에서도 overflow 0
    });

    testWidgets('등록 연타 → create 1회', (tester) async {
      final repo = _FakeWriteRepo(delay: const Duration(milliseconds: 50));
      await _openCompose(tester, repo, <dynamic>[]);
      await _type(tester, '제목입니다', '본문입니다');
      await tester.tap(find.text('등록'));
      await tester.tap(find.text('등록')); // 같은 프레임 연타 — 가드로 1회만
      await tester.pumpAndSettle();
      expect(repo.createCalls, 1);
    });
  });

  group('수정', () {
    testWidgets('기존 제목·본문 prefill', (tester) async {
      final repo = _FakeWriteRepo();
      await _openCompose(tester, repo, <dynamic>[],
          editing: _post(title: '기존제목', body: '기존본문', canEdit: true));
      expect(find.text('기존제목'), findsOneWidget);
      expect(find.text('기존본문'), findsOneWidget);
      expect(find.text('저장'), findsOneWidget); // 수정 모드 버튼
    });

    testWidgets('성공 → pop(true) + update 1회', (tester) async {
      final repo = _FakeWriteRepo();
      final captured = <dynamic>[];
      await _openCompose(tester, repo, captured,
          editing: _post(id: 'pe', title: '기존', body: '기존본문', canEdit: true));
      await tester.enterText(find.byType(TextField).at(0), '수정제목');
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(repo.updateCalls, 1);
      expect(repo.lastTitle, '수정제목');
      expect(captured, [true]);
    });

    testWidgets('실패 → 입력 보존 + 화면 유지', (tester) async {
      final repo = _FakeWriteRepo(throwOnSubmit: const BoardApiException('404', statusCode: 404));
      final captured = <dynamic>[];
      await _openCompose(tester, repo, captured,
          editing: _post(title: '기존', body: '기존본문', canEdit: true));
      await tester.enterText(find.byType(TextField).at(0), '수정시도');
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.pumpAndSettle();
      expect(captured, isEmpty);
      expect(find.text('수정시도'), findsOneWidget);
    });

    testWidgets('저장 연타 → update 1회', (tester) async {
      final repo = _FakeWriteRepo(delay: const Duration(milliseconds: 50));
      final captured = <dynamic>[];
      await _openCompose(tester, repo, captured,
          editing: _post(title: '기존', body: '기존본문', canEdit: true));
      await tester.enterText(find.byType(TextField).at(0), '수정제목');
      await tester.pump();
      await tester.tap(find.text('저장'));
      await tester.tap(find.text('저장')); // 같은 프레임 연타 — 가드로 1회
      await tester.pumpAndSettle();
      expect(repo.updateCalls, 1);
      expect(captured, [true]);
    });
  });

  group('이탈 경고', () {
    testWidgets('변경 있으면 뒤로 시 폐기 확인 다이얼로그', (tester) async {
      final repo = _FakeWriteRepo();
      await _openCompose(tester, repo, <dynamic>[]);
      await _type(tester, '쓰던글', '쓰던본문');
      // AppBar 뒤로가기
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('작성을 취소할까요?'), findsOneWidget); // 폐기 확인
      await tester.tap(find.text('계속 작성'));
      await tester.pumpAndSettle();
      expect(find.byType(BoardComposeScreen), findsOneWidget); // 화면 유지
    });
  });

  group('상세 메뉴/삭제', () {
    Future<void> pumpDetail(WidgetTester t, _FakeDetailRepo repo, List<dynamic> captured) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open'),
                onPressed: () async => captured.add(await Navigator.of(ctx).push(
                    MaterialPageRoute(
                        builder: (_) => BoardDetailScreen(
                            postId: repo.post.id, repository: repo, summary: repo.post)))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('open')));
      await t.pumpAndSettle();
    }

    testWidgets('타인 글(canEdit/canDelete false) → ⋯ 메뉴 미노출', (tester) async {
      final repo = _FakeDetailRepo(_post(canEdit: false, canDelete: false));
      await pumpDetail(tester, repo, <dynamic>[]);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('공식 공지(notice) → ⋯ 메뉴 미노출', (tester) async {
      final repo = _FakeDetailRepo(
          _post(type: BoardType.notice, canEdit: false, canDelete: false));
      await pumpDetail(tester, repo, <dynamic>[]);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });

    testWidgets('본인 글 → ⋯ 메뉴(수정/삭제) 노출', (tester) async {
      final repo = _FakeDetailRepo(_post(canEdit: true, canDelete: true));
      await pumpDetail(tester, repo, <dynamic>[]);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('수정'), findsOneWidget);
      expect(find.text('삭제'), findsOneWidget);
    });

    testWidgets('삭제 확인 취소 → delete 미호출', (tester) async {
      final repo = _FakeDetailRepo(_post(canEdit: true, canDelete: true));
      await pumpDetail(tester, repo, <dynamic>[]);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('글을 삭제할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 0);
    });

    testWidgets('삭제 성공 → delete 1회 + 상세 닫힘(deleted 신호)', (tester) async {
      final repo = _FakeDetailRepo(_post(canEdit: true, canDelete: true));
      final captured = <dynamic>[];
      await pumpDetail(tester, repo, captured);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제')); // 다이얼로그 확인
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 1);
      expect(captured, ['deleted']); // 목록으로 변경 신호
    });

    testWidgets('삭제 실패 → delete 1회 + 상세 유지(미pop)·메뉴·내용 보존 + 재시도 가능', (tester) async {
      final repo = _FakeDetailRepo(_post(canEdit: true, canDelete: true),
          deleteThrows: const BoardApiException('서버 오류', statusCode: 500));
      final captured = <dynamic>[];
      await pumpDetail(tester, repo, captured);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제')); // 확인
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 1);
      expect(captured, isEmpty); // pop 안 됨(deleted 미반환)
      expect(find.byType(BoardDetailScreen), findsOneWidget); // 상세 유지
      expect(find.byIcon(Icons.more_vert), findsOneWidget); // 메뉴 유지
      expect(find.text('본문'), findsOneWidget); // 내용 유지
      // 재시도 가능
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(repo.deleteCalls, 2); // 재시도 호출됨
    });
  });

  group('반응형(작성 화면)', () {
    for (final size in const [Size(320, 568), Size(375, 667), Size(430, 932)]) {
      for (final scale in const [1.0, 1.3, 1.6]) {
        testWidgets('overflow 0 — ${size.width.toInt()}x${size.height.toInt()} @x$scale + 키보드',
            (tester) async {
          tester.view.devicePixelRatio = 3.0;
          tester.view.physicalSize = size * 3.0;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            home: Builder(
              builder: (ctx) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 300), // 키보드 열림
                  padding: const EdgeInsets.only(top: 47, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
                ),
                child: BoardComposeScreen(repository: _FakeWriteRepo()),
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          // 등록 버튼이 키보드와 무관하게 AppBar 에 노출
          expect(find.text('등록'), findsOneWidget);
        });
      }
    }
  });
}
