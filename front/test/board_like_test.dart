import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/board_detail_screen.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 좋아요 — 모델 파싱 + 상세 낙관적 토글/보정/롤백 위젯 테스트. 실네트워크 없음.

class _LikeRepo extends BoardRepository {
  final BoardPost detail;
  int likeCalls = 0;
  int unlikeCalls = 0;
  final BoardLikeResult? likeResult;
  final BoardLikeResult? unlikeResult;
  final Object? likeThrows;
  final Object? unlikeThrows;
  final Duration delay;
  _LikeRepo(this.detail,
      {this.likeResult,
      this.unlikeResult,
      this.likeThrows,
      this.unlikeThrows,
      this.delay = Duration.zero});

  @override
  Future<BoardPost?> fetchDetail(String id) async => detail;

  @override
  Future<BoardLikeResult> likePost(String id) async {
    likeCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (likeThrows != null) throw likeThrows!;
    return likeResult ?? const BoardLikeResult(likedByMe: true, likeCount: 1);
  }

  @override
  Future<BoardLikeResult> unlikePost(String id) async {
    unlikeCalls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (unlikeThrows != null) throw unlikeThrows!;
    return unlikeResult ?? const BoardLikeResult(likedByMe: false, likeCount: 0);
  }
}

BoardPost _free({bool liked = false, int count = 0}) => BoardPost(
      id: 'p1',
      type: BoardType.free,
      title: '제목',
      body: '본문',
      author: '글쓴이',
      createdAt: DateTime(2026, 6, 24, 10),
      likedByMe: liked,
      likeCount: count,
    );

Map<String, dynamic> _json({Object? likedByMe, Object? likeCount}) {
  final m = <String, dynamic>{
    'id': 'p1',
    'type': 'free',
    'title': 't',
    'body': 'b',
    'author': 'a',
    'createdAt': '2026-06-24T10:00:00',
  };
  if (likedByMe != null) m['likedByMe'] = likedByMe;
  if (likeCount != null) m['likeCount'] = likeCount;
  return m;
}

Future<void> _pump(WidgetTester t, _LikeRepo r) async {
  await t.pumpWidget(MaterialApp(home: BoardDetailScreen(postId: 'p1', repository: r)));
  await t.pumpAndSettle();
}

void main() {
  group('모델 파싱', () {
    test('likedByMe true/false', () {
      expect(BoardPost.fromJson(_json(likedByMe: true)).likedByMe, isTrue);
      expect(BoardPost.fromJson(_json(likedByMe: false)).likedByMe, isFalse);
    });
    test('likedByMe 누락 → false (구버전 호환)', () {
      expect(BoardPost.fromJson(_json()).likedByMe, isFalse);
    });
    test('likedByMe 잘못된 타입 → false', () {
      expect(BoardPost.fromJson(_json(likedByMe: 'true')).likedByMe, isFalse);
      expect(BoardPost.fromJson(_json(likedByMe: 1)).likedByMe, isFalse);
    });
    test('likeCount 누락 → 0', () {
      expect(BoardPost.fromJson(_json()).likeCount, 0);
    });
    test('likeCount 음수 → 0 (음수 표시 방지)', () {
      expect(BoardPost.fromJson(_json(likeCount: -5)).likeCount, 0);
    });
    test('likeCount 정상 파싱', () {
      expect(BoardPost.fromJson(_json(likeCount: 7)).likeCount, 7);
    });
  });

  group('상세 낙관적 토글', () {
    testWidgets('초기 상태 = likedByMe/likeCount 반영', (t) async {
      await _pump(t, _LikeRepo(_free(liked: true, count: 5)));
      expect(find.byIcon(Icons.favorite), findsOneWidget); // 채운 하트
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('좋아요 → 즉시 채움 +1 → 서버값으로 보정', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 4),
          likeResult: const BoardLikeResult(likedByMe: true, likeCount: 9), // 서버는 9
          delay: const Duration(milliseconds: 30));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite_border));
      await t.pump(); // 낙관적 프레임(서버 응답 전)
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('5'), findsOneWidget); // 4+1 낙관적
      await t.pumpAndSettle(); // 서버 응답
      expect(r.likeCalls, 1);
      expect(find.text('9'), findsOneWidget); // 서버값 보정
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });

    testWidgets('취소 → 즉시 비움 -1 → 서버값 보정', (t) async {
      final r = _LikeRepo(_free(liked: true, count: 5),
          unlikeResult: const BoardLikeResult(likedByMe: false, likeCount: 4),
          delay: const Duration(milliseconds: 30));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite));
      await t.pump();
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      await t.pumpAndSettle();
      expect(r.unlikeCalls, 1);
      expect(find.text('4'), findsOneWidget);
    });

    testWidgets('좋아요 실패 → 이전 상태/카운트 정확 롤백·화면 유지', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 3),
          likeThrows: const BoardApiException('서버오류', statusCode: 500),
          delay: const Duration(milliseconds: 30));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite_border));
      await t.pump();
      expect(find.text('4'), findsOneWidget); // 낙관적 3+1
      await t.pumpAndSettle(); // 실패 → 롤백
      expect(r.likeCalls, 1);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget); // 빈 하트 복귀
      expect(find.text('3'), findsOneWidget); // 카운트 복귀
      expect(find.byType(BoardDetailScreen), findsOneWidget);
    });

    testWidgets('취소 실패 → 정확 롤백(채움/카운트 복귀)', (t) async {
      final r = _LikeRepo(_free(liked: true, count: 8),
          unlikeThrows: const BoardApiException('미존재', statusCode: 404),
          delay: const Duration(milliseconds: 30));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('좋아요 401 → 롤백·busy 해제·인라인 토스트 없음(전역 lifecycle 소유)', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 3),
          likeThrows: const BoardApiException('로그인이 필요해요.', statusCode: 401),
          delay: const Duration(milliseconds: 30));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite_border));
      await t.pumpAndSettle();
      expect(r.likeCalls, 1);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget); // 롤백
      expect(find.text('3'), findsOneWidget);
      expect(find.text('로그인이 필요해요.'), findsNothing); // 화면 인라인 토스트 없음(전역이 로그아웃 처리)
      await t.tap(find.byIcon(Icons.favorite_border)); // busy 해제 → 재시도 가능
      await t.pumpAndSettle();
      expect(r.likeCalls, 2);
    });

    testWidgets('카운트 0에서 취소 낙관적 → 음수 없음', (t) async {
      final r = _LikeRepo(_free(liked: true, count: 0),
          unlikeResult: const BoardLikeResult(likedByMe: false, likeCount: 0));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite));
      await t.pump();
      expect(find.text('-1'), findsNothing); // 음수 표시 없음
      await t.pumpAndSettle();
    });

    testWidgets('연타 → repository 1회', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 0),
          delay: const Duration(milliseconds: 60));
      await _pump(t, r);
      await t.tap(find.byIcon(Icons.favorite_border));
      await t.tap(find.byIcon(Icons.favorite_border)); // 같은 프레임 연타(미rebuild)
      await t.pumpAndSettle();
      expect(r.likeCalls, 1);
    });
  });

  group('노출 제어', () {
    testWidgets('공지 상세 → 하트 미노출', (t) async {
      final notice = BoardPost(
          id: 'p1', type: BoardType.notice, title: '공지', body: '본문', author: '운영',
          createdAt: DateTime(2026, 6, 24, 10));
      await _pump(t, _LikeRepo(notice));
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });

    testWidgets('자유 외 커뮤니티(거래후기) → 하트 미노출', (t) async {
      final tr = BoardPost(
          id: 'p1', type: BoardType.tradeReview, title: '후기', body: '본문', author: 'u',
          createdAt: DateTime(2026, 6, 24, 10), likeCount: 3, likedByMe: true);
      await _pump(t, _LikeRepo(tr));
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
    });
  });

  group('목록 반영(pop result)', () {
    testWidgets('상세 좋아요 후 뒤로 → changed 신호', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 0));
      Object? popResult = 'SENTINEL';
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => popResult = await Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => BoardDetailScreen(postId: 'p1', repository: r))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.favorite_border)); // 좋아요
      await t.pumpAndSettle();
      await t.tap(find.byType(BackButton)); // AppBar 뒤로
      await t.pumpAndSettle();
      expect(popResult, 'changed');
    });

    testWidgets('변경 없이 뒤로 → null(목록 미갱신)', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 0));
      Object? popResult = 'SENTINEL';
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => popResult = await Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => BoardDetailScreen(postId: 'p1', repository: r))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      expect(popResult, isNull);
    });
  });

  group('요청 중 뒤로가기 차단(race)', () {
    // AppBar 뒤로(BackButton=maybePop)와 iOS swipe-back 은 동일하게 PopScope(canPop:false).onPopInvoked 경로.
    Future<void> open(WidgetTester t, _LikeRepo r, void Function(Object?) sink) async {
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => sink(await Navigator.of(ctx).push(
                    MaterialPageRoute(builder: (_) => BoardDetailScreen(postId: 'p1', repository: r)))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('좋아요 요청 중 뒤로 차단 → 완료 후 뒤로=changed', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 2),
          likeResult: const BoardLikeResult(likedByMe: true, likeCount: 3),
          delay: const Duration(milliseconds: 120));
      Object? popResult = 'SENTINEL';
      await open(t, r, (v) => popResult = v);

      await t.tap(find.byIcon(Icons.favorite_border)); // 지연 요청 시작
      await t.pump();
      await t.tap(find.byType(BackButton)); // 요청 중 뒤로 시도
      await t.pump();
      expect(find.byType(BoardDetailScreen), findsOneWidget); // 안 닫힘
      expect(popResult, 'SENTINEL'); // pop 안 됨

      await t.pumpAndSettle(); // 요청 완료
      expect(r.likeCalls, 1);
      await t.tap(find.byType(BackButton)); // 이제 뒤로 가능
      await t.pumpAndSettle();
      expect(popResult, 'changed'); // 목록 재조회 신호
    });

    testWidgets('좋아요 실패 요청 중 뒤로 차단 → 롤백 후 뒤로=null(변경없음)', (t) async {
      final r = _LikeRepo(_free(liked: false, count: 2),
          likeThrows: const BoardApiException('서버오류', statusCode: 500),
          delay: const Duration(milliseconds: 120));
      Object? popResult = 'SENTINEL';
      await open(t, r, (v) => popResult = v);

      await t.tap(find.byIcon(Icons.favorite_border));
      await t.pump();
      await t.tap(find.byType(BackButton)); // 요청 중 차단
      await t.pump();
      expect(find.byType(BoardDetailScreen), findsOneWidget);
      expect(popResult, 'SENTINEL');

      await t.pumpAndSettle(); // 실패 → 롤백
      expect(r.likeCalls, 1);
      expect(find.byIcon(Icons.favorite_border), findsOneWidget); // 롤백
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.byType(BackButton)); // 실패 후 뒤로 정상
      await t.pumpAndSettle();
      expect(popResult, isNull); // 서버 변경 없음
    });
  });

  group('반응형', () {
    final longName = '가나다라마바사아자차카타파하갸';
    for (final size in const [Size(320, 568), Size(375, 667), Size(430, 932)]) {
      for (final scale in const [1.0, 1.3, 1.6]) {
        testWidgets('overflow 0 — ${size.width.toInt()}x${size.height.toInt()} @x$scale (하트+댓글+키보드)',
            (t) async {
          t.view.devicePixelRatio = 3.0;
          t.view.physicalSize = size * 3.0;
          addTearDown(t.view.reset);
          final detail = BoardPost(
            id: 'p1', type: BoardType.free, title: '제목 ' * 6, body: '본문 ' * 40,
            author: longName, createdAt: DateTime(2026, 6, 24, 10),
            likedByMe: true, likeCount: 9999,
            comments: [
              BoardComment(
                  id: 't1', author: longName, body: '댓글 ' * 10,
                  createdAt: DateTime(2026, 6, 24, 10), mine: true, canDelete: true,
                  canReply: true, replyTargetCommentId: 't1',
                  replies: [
                    BoardComment(
                        id: 'r1', author: longName, body: '대댓글 ' * 6,
                        createdAt: DateTime(2026, 6, 24, 10), canReply: true, replyTargetCommentId: 't1')
                  ]),
            ],
          );
          await t.pumpWidget(MaterialApp(
            home: Builder(
              builder: (ctx) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                  textScaler: TextScaler.linear(scale),
                  viewInsets: const EdgeInsets.only(bottom: 300),
                  padding: const EdgeInsets.only(top: 47, bottom: 34),
                  viewPadding: const EdgeInsets.only(top: 47, bottom: 34),
                ),
                child: BoardDetailScreen(postId: 'p1', repository: _LikeRepo(detail)),
              ),
            ),
          ));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        });
      }
    }
  });
}
