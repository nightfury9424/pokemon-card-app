import 'package:flutter_test/flutter_test.dart';
import 'package:front/features/board/models/board_post.dart';

/// 게시판 모델 소유권·액션 플래그 파싱 — 안전 기본값(누락/잘못된 타입 → false/null) 검증.
/// UI 미연결(이 라운드는 모델 파싱만). 백엔드·앱 배포 시점이 달라도 깨지지 않아야 함.
void main() {
  group('BoardPost 플래그 파싱', () {
    test('새 백엔드 JSON 전체 필드 파싱', () {
      final p = BoardPost.fromJson({
        'id': 'p1', 'type': 'free', 'title': '제목', 'body': '본문', 'author': '글쓴이',
        'createdAt': '2026-06-24T10:00:00', 'commentCount': 3,
        'mine': true, 'canEdit': true, 'canDelete': true, 'canReport': false, 'canBlock': false,
      });
      expect(p.mine, isTrue);
      expect(p.canEdit, isTrue);
      expect(p.canDelete, isTrue);
      expect(p.canReport, isFalse);
      expect(p.canBlock, isFalse);
      // 기존 필드 회귀
      expect(p.title, '제목');
      expect(p.author, '글쓴이');
      expect(p.type, BoardType.free);
      expect(p.commentCount, 3);
    });

    test('구버전 JSON(플래그 전부 없음) → 전부 false, 크래시 없음', () {
      final p = BoardPost.fromJson({
        'id': 'p1', 'type': 'notice', 'title': 't', 'body': 'b', 'author': '운영팀',
        'createdAt': '2026-06-24T10:00:00',
      });
      expect(p.mine, isFalse);
      expect(p.canEdit, isFalse);
      expect(p.canDelete, isFalse);
      expect(p.canReport, isFalse);
      expect(p.canBlock, isFalse);
    });

    test('잘못된 boolean 타입(문자열/숫자/null) → 안전 false', () {
      final p = BoardPost.fromJson({
        'id': 'p1', 'type': 'free', 'title': 't', 'body': 'b', 'author': 'a',
        'createdAt': '2026-06-24T10:00:00',
        'mine': 'true', 'canEdit': 1, 'canReport': null, 'canBlock': 'false',
      });
      expect(p.mine, isFalse);     // 문자열 'true' → false
      expect(p.canEdit, isFalse);  // 숫자 1 → false
      expect(p.canReport, isFalse); // null → false
      expect(p.canBlock, isFalse); // 문자열 'false' → false
    });
  });

  group('BoardComment 플래그 파싱', () {
    test('댓글·대댓글 플래그 + replyTargetCommentId(최상위 부모)', () {
      final c = BoardComment.fromJson({
        'id': 'c1', 'author': '닉', 'body': '댓글', 'createdAt': '2026-06-24T10:00:00',
        'mine': false, 'canDelete': false, 'canReply': true, 'replyTargetCommentId': 'c1',
        'canReport': true, 'canBlock': true,
        'replies': [
          {
            'id': 'r1', 'author': '닉2', 'body': '답글', 'createdAt': '2026-06-24T11:00:00',
            'canReply': true, 'replyTargetCommentId': 'c1', 'canReport': true,
          },
        ],
      });
      expect(c.canReply, isTrue);
      expect(c.replyTargetCommentId, 'c1');
      expect(c.canReport, isTrue);
      expect(c.canBlock, isTrue);
      final r = c.replies.single;
      expect(r.canReply, isTrue);
      expect(r.replyTargetCommentId, 'c1'); // 대댓글도 최상위 부모 가리킴
      expect(r.canReport, isTrue);
      expect(r.canBlock, isFalse); // JSON 누락 → false
    });

    test('replyTargetCommentId 누락/null/빈문자 → null', () {
      final missing = BoardComment.fromJson({
        'id': 'c1', 'author': 'a', 'body': 'b', 'createdAt': '2026-06-24T10:00:00',
      });
      expect(missing.replyTargetCommentId, isNull);
      expect(missing.canReply, isFalse);
      final explicitNull = BoardComment.fromJson({
        'id': 'c2', 'author': 'a', 'body': 'b', 'createdAt': '2026-06-24T10:00:00',
        'replyTargetCommentId': null,
      });
      expect(explicitNull.replyTargetCommentId, isNull);
      final empty = BoardComment.fromJson({
        'id': 'c3', 'author': 'a', 'body': 'b', 'createdAt': '2026-06-24T10:00:00',
        'replyTargetCommentId': '',
      });
      expect(empty.replyTargetCommentId, isNull);
    });

    test('구버전 댓글(플래그 없음) → 안전 기본값 + 트리/기존 필드 회귀', () {
      final c = BoardComment.fromJson({
        'id': 'c1', 'author': '운영팀', 'body': '댓글', 'createdAt': '2026-06-24T10:00:00',
        'isAdmin': true,
        'replies': [
          {'id': 'r1', 'author': 'u', 'body': '답글', 'createdAt': '2026-06-24T11:00:00'},
        ],
      });
      expect(c.mine, isFalse);
      expect(c.canDelete, isFalse);
      expect(c.canReply, isFalse);
      expect(c.replyTargetCommentId, isNull);
      expect(c.canReport, isFalse);
      expect(c.canBlock, isFalse);
      // 기존 필드/트리 회귀
      expect(c.isAdmin, isTrue);
      expect(c.body, '댓글');
      expect(c.replies.single.body, '답글');
    });

    test('잘못된 boolean 타입 → 안전 false', () {
      final c = BoardComment.fromJson({
        'id': 'c1', 'author': 'a', 'body': 'b', 'createdAt': '2026-06-24T10:00:00',
        'canReply': 'yes', 'mine': 0, 'canReport': [],
      });
      expect(c.canReply, isFalse);
      expect(c.mine, isFalse);
      expect(c.canReport, isFalse);
    });
  });
}
