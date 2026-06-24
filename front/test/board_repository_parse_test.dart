import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/data/board_repository.dart';
import 'package:front/features/board/models/board_post.dart';

/// 게시판 읽기 견고화 게이트 검증 (네트워크와 분리된 순수 파서).
/// ① ReturnData.status=fail(HTTP 200이어도) → 실패  ② unknown type/잘못된 날짜/형식오류 → 파싱예외
/// (조용히 빈 목록·now() 위장 금지).
void main() {
  Map<String, dynamic> ok(Object? data) => {
    'status': 'success',
    'code': 'S000',
    'message': '성공',
    'data': data,
  };

  Map<String, dynamic> postJson({
    String id = 'p1',
    String type = 'free',
    String createdAt = '2026-06-23T10:00:00',
    int commentCount = 3,
    List? comments,
  }) => {
    'id': id,
    'type': type,
    'title': '제목',
    'body': '본문',
    'author': '닉네임',
    'createdAt': createdAt,
    'viewCount': 10,
    'likeCount': 2,
    'isPinned': false,
    'isAnswered': false,
    'commentCount': commentCount,
    'comments': ?comments,
  };

  group('토큰 파서', () {
    test('알려진 토큰 → enum', () {
      expect(boardTypeFromToken('tradeReview'), BoardType.tradeReview);
      expect(boardTypeFromToken('notice'), BoardType.notice);
    });
    test('알 수 없는 토큰 → null(byName 처럼 throw 안 함)', () {
      expect(boardTypeFromToken('weirdType'), isNull);
      expect(boardTypeFromToken(null), isNull);
    });
  });

  group('목록 파싱', () {
    test('정상 → posts/페이지네이션/서버 commentCount', () {
      final res = ok({
        'content': [postJson(id: 'a', commentCount: 7), postJson(id: 'b')],
        'page': 0,
        'size': 20,
        'totalElements': 2,
        'totalPages': 1,
      });
      final r = BoardListResult.parse(res);
      expect(r.posts.length, 2);
      expect(r.posts.first.id, 'a');
      expect(
        r.posts.first.commentCount,
        7,
      ); // 서버 listCommentCount 사용(목록엔 comments 없음)
      expect(r.hasMore, isFalse);
    });

    test('공지(official notice) 피드 항목 — 홈 배너 계약 필드 파싱', () {
      // 백엔드 BoardPostSummaryDto(official notice) JSON → Flutter BoardPost.fromJson 일치 검증.
      final res = ok({
        'content': [postJson(id: 'n1', type: 'notice')],
        'page': 0,
        'size': 5,
        'totalElements': 1,
        'totalPages': 1,
      });
      final p = BoardListResult.parse(res).posts.single;
      expect(p.type, BoardType.notice);
      expect(p.id, 'n1');
      expect(p.title, '제목'); // 배너 표시
      expect(p.body, '본문'); // 상세 본문(전문)
    });

    test('hasMore — page 0 / totalPages 3 → true', () {
      final res = ok({
        'content': [],
        'page': 0,
        'size': 20,
        'totalElements': 50,
        'totalPages': 3,
      });
      expect(BoardListResult.parse(res).hasMore, isTrue);
    });

    test('★status=fail(HTTP 200) → BoardApiException (성공 오인 금지)', () {
      final res = {
        'status': 'fail',
        'code': 'E003',
        'message': '잘못된 요청',
        'data': {'content': []},
      };
      expect(
        () => BoardListResult.parse(res),
        throwsA(isA<BoardApiException>().having((e) => e.code, 'code', 'E003')),
      );
    });

    test('★unknown type → BoardParseException (빈 목록 위장 금지)', () {
      final res = ok({
        'content': [postJson(type: 'nopeType')],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
      });
      expect(
        () => BoardListResult.parse(res),
        throwsA(isA<BoardParseException>()),
      );
    });

    test('★잘못된 createdAt → BoardParseException (now() 위장 금지)', () {
      final res = ok({
        'content': [postJson(createdAt: 'not-a-date')],
        'page': 0,
        'size': 20,
        'totalElements': 1,
        'totalPages': 1,
      });
      expect(
        () => BoardListResult.parse(res),
        throwsA(isA<BoardParseException>()),
      );
    });

    test('data 형식 오류 → BoardParseException', () {
      expect(
        () => BoardListResult.parse(ok('not-a-map')),
        throwsA(isA<BoardParseException>()),
      );
    });

    test('content 형식 오류 → BoardParseException', () {
      expect(
        () => BoardListResult.parse(ok({'content': 'nope'})),
        throwsA(isA<BoardParseException>()),
      );
    });
  });

  group('상세 파싱', () {
    test('정상 → 댓글 1단 트리 + isAccepted', () {
      final res = ok(
        postJson(
          id: 'q1',
          type: 'qna',
          comments: [
            {
              'id': 'c1',
              'author': '운영팀',
              'body': '답',
              'createdAt': '2026-06-23T11:00:00',
              'isAdmin': true,
              'isAccepted': true,
              'replies': [
                {
                  'id': 'r1',
                  'author': 'u',
                  'body': '감사',
                  'createdAt': '2026-06-23T12:00:00',
                  'isAdmin': false,
                  'isAccepted': false,
                  'replies': [],
                },
              ],
            },
          ],
        ),
      );
      final post = parseBoardDetail(res);
      expect(post.type, BoardType.qna);
      expect(post.comments.length, 1);
      expect(post.comments.first.isAccepted, isTrue);
      expect(post.comments.first.replies.length, 1);
      // 상세는 listCommentCount 없을 수도 있으나 여기선 commentCount 키 포함 → 서버값.
    });

    test('status=fail → BoardApiException', () {
      final res = {
        'status': 'fail',
        'code': 'E002',
        'message': '없음',
        'data': null,
      };
      expect(() => parseBoardDetail(res), throwsA(isA<BoardApiException>()));
    });

    test('data null/형식오류 → BoardParseException', () {
      expect(
        () => parseBoardDetail(ok(null)),
        throwsA(isA<BoardParseException>()),
      );
    });

    test('id 누락 → BoardParseException', () {
      final bad = postJson()..remove('id');
      expect(
        () => parseBoardDetail(ok(bad)),
        throwsA(isA<BoardParseException>()),
      );
    });
  });
}
