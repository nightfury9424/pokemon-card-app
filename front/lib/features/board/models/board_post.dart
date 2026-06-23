import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// 게시판 글 종류. (post-launch 신기능 — 프론트 스캐폴딩, 백엔드는 승인 후 연결)
enum BoardType { notice, event, patch, free, tradeReview, scamAlert, qna }

/// 서버 type 토큰(camelCase) → BoardType. 알 수 없는 값은 **null**(상위에서 오류 상태로 보고).
/// values.byName 직접 호출 금지(미지원 토큰에 ArgumentError 던져 화면 전체가 죽음).
BoardType? boardTypeFromToken(String? token) {
  if (token == null) return null;
  for (final t in BoardType.values) {
    if (t.name == token) return t;
  }
  return null;
}

// 파싱 정책: 알 수 없는 값/형식은 now()·기본값으로 위장하지 않고 FormatException →
// 상위(BoardRepository)가 BoardParseException 으로 변환해 화면 오류 상태로 보고.
String _reqString(Map j, String key) {
  final v = j[key];
  if (v is String && v.isNotEmpty) return v;
  throw FormatException('게시판 응답 필드 누락/형식오류: $key=$v');
}

DateTime _reqDateTime(Map j, String key) {
  final v = j[key];
  final dt = v is String ? DateTime.tryParse(v) : null;
  if (dt == null) throw FormatException('게시판 응답 날짜 파싱 오류: $key=$v');
  return dt.toLocal();
}

/// 서버 액션 플래그 안전 파싱 — 누락/잘못된 타입(문자열·숫자 등)은 **false**.
/// 백엔드·앱 배포 시점이 달라 필드가 없어도 크래시 없이, 액션 버튼이 잘못 열리지 않게 기본 false.
bool _flag(Map j, String key) {
  final v = j[key];
  return v is bool ? v : false;
}

/// 카운트 안전 파싱 — 없거나 숫자 아니면 0, 음수는 0으로(음수 표시 방지).
int _nonNegInt(Object? v) {
  final n = v is num ? v.toInt() : 0;
  return n < 0 ? 0 : n;
}

/// nullable string 안전 파싱 — 없거나 문자열 아니면 null. (replyTargetCommentId 등)
String? _nullableString(Map j, String key) {
  final v = j[key];
  return v is String && v.isNotEmpty ? v : null;
}

/// 게시판 상대시간 표시(실시간 기준). ★목업의 고정 _now 가 아니라 DateTime.now() 사용.
String boardRelativeTime(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inMinutes < 1) return '방금';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${t.month}/${t.day}';
}

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

  // 서버 계산 액션 플래그(viewerId 기준). UI 표시용 — 권한은 서버가 쓰기 시 재검증.
  // 누락 시 안전 기본값(false/null) — 구버전 백엔드 호환. raw authorId 는 받지 않음(닉네임으로 mine 추정 금지).
  final bool mine;
  final bool canDelete;
  final bool canReply;
  final String? replyTargetCommentId; // 답글 작성 시 항상 이 값(최상위 댓글) 전송. 없으면 답글 불가.
  final bool canReport;
  final bool canBlock;

  const BoardComment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.isAdmin = false,
    this.isAccepted = false,
    this.replies = const [],
    this.mine = false,
    this.canDelete = false,
    this.canReply = false,
    this.replyTargetCommentId,
    this.canReport = false,
    this.canBlock = false,
  });

  /// 백엔드 BoardCommentDto 직렬화 계약. 삭제댓글은 서버가 placeholder 노드로 채워 보냄(non-null 보장).
  /// id/createdAt 형식 오류는 위장 없이 FormatException(상위에서 BoardParseException).
  factory BoardComment.fromJson(Map<String, dynamic> j) => BoardComment(
        id: _reqString(j, 'id'),
        author: (j['author'] as String?) ?? '',
        body: (j['body'] as String?) ?? '',
        createdAt: _reqDateTime(j, 'createdAt'),
        isAdmin: (j['isAdmin'] as bool?) ?? false,
        isAccepted: (j['isAccepted'] as bool?) ?? false,
        replies: ((j['replies'] as List?) ?? const [])
            .map((e) => BoardComment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        mine: _flag(j, 'mine'),
        canDelete: _flag(j, 'canDelete'),
        canReply: _flag(j, 'canReply'),
        replyTargetCommentId: _nullableString(j, 'replyTargetCommentId'),
        canReport: _flag(j, 'canReport'),
        canBlock: _flag(j, 'canBlock'),
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
  final bool likedByMe; // 서버 계산: viewer 가 좋아요했는지(누락/잘못된 타입 → false)
  final bool isPinned;
  final bool isAnswered; // Q&A: 답변 달림
  final List<BoardComment> comments;

  /// 목록 응답(BoardPostSummaryDto)의 서버 라이브 집계값. 상세/목업은 null → comments 에서 계산.
  final int? listCommentCount;

  // 서버 계산 액션 플래그(viewerId 기준). 누락 시 false — 구버전 백엔드 호환. raw authorId 미수신.
  final bool mine;
  final bool canEdit;
  final bool canDelete;
  final bool canReport;
  final bool canBlock;

  const BoardPost({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.author,
    required this.createdAt,
    this.viewCount = 0,
    this.likeCount = 0,
    this.likedByMe = false,
    this.isPinned = false,
    this.isAnswered = false,
    this.comments = const [],
    this.listCommentCount,
    this.mine = false,
    this.canEdit = false,
    this.canDelete = false,
    this.canReport = false,
    this.canBlock = false,
  });

  /// 백엔드 BoardPostSummaryDto(목록)/BoardPostDetailDto(상세) 공통 파서.
  /// 목록엔 comments 없음 → listCommentCount 로 댓글 수 표시. 상세엔 comments 있음.
  /// 알 수 없는 type/잘못된 날짜/id 누락은 위장 없이 FormatException(상위에서 BoardParseException).
  factory BoardPost.fromJson(Map<String, dynamic> j) {
    final type = boardTypeFromToken(j['type'] as String?);
    if (type == null) {
      throw FormatException('알 수 없는 게시글 type: ${j['type']}');
    }
    return BoardPost(
      id: _reqString(j, 'id'),
      type: type,
      title: (j['title'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
      author: (j['author'] as String?) ?? '',
      createdAt: _reqDateTime(j, 'createdAt'),
      viewCount: (j['viewCount'] as num?)?.toInt() ?? 0,
      // 음수(서버는 COUNT라 0+, 방어적으로) 표시 방지.
      likeCount: _nonNegInt(j['likeCount']),
      likedByMe: _flag(j, 'likedByMe'),
      isPinned: (j['isPinned'] as bool?) ?? false,
      isAnswered: (j['isAnswered'] as bool?) ?? false,
      comments: ((j['comments'] as List?) ?? const [])
          .map((e) => BoardComment.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      listCommentCount: (j['commentCount'] as num?)?.toInt(),
      mine: _flag(j, 'mine'),
      canEdit: _flag(j, 'canEdit'),
      canDelete: _flag(j, 'canDelete'),
      canReport: _flag(j, 'canReport'),
      canBlock: _flag(j, 'canBlock'),
    );
  }

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
