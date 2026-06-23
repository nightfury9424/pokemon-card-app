import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// 게시판 글 종류. (post-launch 신기능 — 프론트 스캐폴딩, 백엔드는 승인 후 연결)
enum BoardType { notice, event, patch, free, tradeReview, scamAlert, qna }

extension BoardTypeMeta on BoardType {
  /// 관리자만 작성 (읽기전용 공지성).
  bool get isAdmin =>
      this == BoardType.notice || this == BoardType.event || this == BoardType.patch;

  String get label {
    switch (this) {
      case BoardType.notice: return '공지';
      case BoardType.event: return '이벤트';
      case BoardType.patch: return '패치노트';
      case BoardType.free: return '자유';
      case BoardType.tradeReview: return '거래후기';
      case BoardType.scamAlert: return '사기주의';
      case BoardType.qna: return 'Q&A';
    }
  }

  Color get color {
    switch (this) {
      case BoardType.notice: return AppColors.blue;
      case BoardType.event: return AppColors.gold;
      case BoardType.patch: return const Color(0xFF9575CD);
      case BoardType.free: return AppColors.textSecondary;
      case BoardType.tradeReview: return AppColors.green;
      case BoardType.scamAlert: return AppColors.red;
      case BoardType.qna: return AppColors.blueLight;
    }
  }

  IconData get icon {
    switch (this) {
      case BoardType.notice: return Icons.campaign_outlined;
      case BoardType.event: return Icons.celebration_outlined;
      case BoardType.patch: return Icons.new_releases_outlined;
      case BoardType.free: return Icons.chat_bubble_outline;
      case BoardType.tradeReview: return Icons.verified_outlined;
      case BoardType.scamAlert: return Icons.warning_amber_rounded;
      case BoardType.qna: return Icons.help_outline;
    }
  }
}

/// 게시판 섹션 (상단 탭).
enum BoardSection { official, community, qna }

extension BoardSectionMeta on BoardSection {
  String get label {
    switch (this) {
      case BoardSection.official: return '공지·소식';
      case BoardSection.community: return '커뮤니티';
      case BoardSection.qna: return 'Q&A';
    }
  }

  /// 이 섹션에 속하는 글 종류 (카테고리 칩).
  List<BoardType> get types {
    switch (this) {
      case BoardSection.official:
        return const [BoardType.notice, BoardType.event, BoardType.patch];
      case BoardSection.community:
        return const [BoardType.free, BoardType.tradeReview, BoardType.scamAlert];
      case BoardSection.qna:
        return const [BoardType.qna];
    }
  }

  /// 유저가 글 쓸 수 있는 섹션 (관리자 공지섹션은 X).
  bool get userWritable => this != BoardSection.official;
}

class BoardComment {
  final String id;
  final String author;
  final String body;
  final DateTime createdAt;
  final bool isAdmin;
  final bool isAccepted; // Q&A 채택 답변
  final List<BoardComment> replies; // 대댓글 1단계

  const BoardComment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.isAdmin = false,
    this.isAccepted = false,
    this.replies = const [],
  });

  /// 백엔드 BoardCommentDto 직렬화 계약. 삭제댓글은 서버가 placeholder 노드로 채워 보냄(non-null 보장).
  factory BoardComment.fromJson(Map<String, dynamic> j) => BoardComment(
        id: j['id'] as String,
        author: (j['author'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        createdAt:
            DateTime.tryParse((j['createdAt'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
        isAdmin: (j['isAdmin'] as bool?) ?? false,
        isAccepted: (j['isAccepted'] as bool?) ?? false,
        replies: ((j['replies'] as List?) ?? const [])
            .map((e) => BoardComment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class BoardPost {
  final String id;
  final BoardType type;
  final String title;
  final String body;
  final String author;
  final DateTime createdAt;
  final int viewCount;
  final int likeCount;
  final bool isPinned;
  final bool isAnswered; // Q&A: 답변 달림
  final List<BoardComment> comments;

  /// 목록 응답(BoardPostSummaryDto)의 서버 라이브 집계값. 상세/목업은 null → comments 에서 계산.
  final int? listCommentCount;

  const BoardPost({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.author,
    required this.createdAt,
    this.viewCount = 0,
    this.likeCount = 0,
    this.isPinned = false,
    this.isAnswered = false,
    this.comments = const [],
    this.listCommentCount,
  });

  /// 백엔드 BoardPostSummaryDto(목록)/BoardPostDetailDto(상세) 공통 파서.
  /// 목록엔 comments 없음 → listCommentCount 로 댓글 수 표시. 상세엔 comments 있음.
  factory BoardPost.fromJson(Map<String, dynamic> j) => BoardPost(
        id: j['id'] as String,
        type: BoardType.values.byName(j['type'] as String),
        title: (j['title'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        author: (j['author'] as String?) ?? '',
        createdAt:
            DateTime.tryParse((j['createdAt'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
        viewCount: (j['viewCount'] as num?)?.toInt() ?? 0,
        likeCount: (j['likeCount'] as num?)?.toInt() ?? 0,
        isPinned: (j['isPinned'] as bool?) ?? false,
        isAnswered: (j['isAnswered'] as bool?) ?? false,
        comments: ((j['comments'] as List?) ?? const [])
            .map((e) => BoardComment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        listCommentCount: (j['commentCount'] as num?)?.toInt(),
      );

  bool get isAdmin => type.isAdmin;

  int get commentCount {
    if (listCommentCount != null) return listCommentCount!;
    var n = comments.length;
    for (final c in comments) {
      n += c.replies.length;
    }
    return n;
  }
}
