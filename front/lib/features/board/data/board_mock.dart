import '../models/board_post.dart';

/// 게시판 목업 데이터 (백엔드 승인 후 API로 교체).
class BoardMock {
  static final DateTime _now = DateTime(2026, 6, 9, 9, 0);
  static DateTime _ago(Duration d) => _now.subtract(d);

  static final List<BoardPost> posts = [
    // ── 공지·소식 (관리자) ──
    BoardPost(
      id: 'n1', type: BoardType.notice, isPinned: true,
      title: '포켓폴리오 정식 오픈 안내 📣',
      body: '안녕하세요, 포켓폴리오입니다.\n드디어 정식 오픈했어요! 카드 스캔으로 내 컬렉션을 등록하고, 실시간 시세를 추적하고, 안전하게 거래해보세요.\n\n많은 관심 부탁드립니다.',
      author: '운영팀', createdAt: _ago(const Duration(hours: 3)), viewCount: 1284, likeCount: 96,
    ),
    BoardPost(
      id: 'e1', type: BoardType.event,
      title: '🎁 오픈 기념 이벤트 — 첫 스캔 인증하면 추첨!',
      body: '오픈 기념으로 카드 스캔 인증한 분들 중 추첨을 통해 소정의 상품을 드립니다.\n기간: ~6월 30일',
      author: '운영팀', createdAt: _ago(const Duration(hours: 20)), viewCount: 842, likeCount: 134,
    ),
    BoardPost(
      id: 'p1', type: BoardType.patch,
      title: '패치노트 v1.0 — 시세 안정화 & 거래 채팅',
      body: '· KO 예상가 모델 안정화\n· 거래 호가 + 실시간 채팅\n· 그레이딩 실카드 검증\n· 전반적인 성능 개선',
      author: '운영팀', createdAt: _ago(const Duration(days: 1, hours: 4)), viewCount: 521, likeCount: 41,
    ),

    // ── 커뮤니티 (유저) ──
    BoardPost(
      id: 'f1', type: BoardType.free,
      title: '드디어 리자몽 SAR 풀았다 ㅠㅠ',
      body: '한 달을 노렸는데 드디어 손에 넣었어요. 너무 예쁘다…',
      author: '불꽃조련사', createdAt: _ago(const Duration(hours: 5)), viewCount: 312, likeCount: 58,
      comments: [
        BoardComment(id: 'c1', author: '피카츄러버', body: '와 부럽다 ㄷㄷ 상태도 좋네요', createdAt: _ago(const Duration(hours: 4)),
          replies: [BoardComment(id: 'c1r1', author: '불꽃조련사', body: 'ㅎㅎ 감사합니다!', createdAt: _ago(const Duration(hours: 3)))]),
        BoardComment(id: 'c2', author: '수집가K', body: '시세 얼마정도 해요?', createdAt: _ago(const Duration(hours: 2))),
      ],
    ),
    BoardPost(
      id: 'tr1', type: BoardType.tradeReview,
      title: '메가리자몽X 거래 후기 — 매너 최고 👍',
      body: '직거래로 안전하게 잘 받았습니다. 포장도 꼼꼼하시고 응답도 빠르셨어요. 강추!',
      author: '강민형', createdAt: _ago(const Duration(hours: 8)), viewCount: 198, likeCount: 23,
      comments: [
        BoardComment(id: 'c3', author: '거래왕', body: '저도 이분이랑 거래했는데 좋았어요', createdAt: _ago(const Duration(hours: 6))),
      ],
    ),
    BoardPost(
      id: 'sa1', type: BoardType.scamAlert,
      title: '⚠️ 선입금 유도 사기 주의하세요',
      body: '"지금 입금 안 하면 다른 사람한테 판다"며 선입금 유도하는 계정 조심하세요. 꼭 안전결제/직거래로 진행하세요.',
      author: '안전지킴이', createdAt: _ago(const Duration(hours: 12)), viewCount: 456, likeCount: 87,
      comments: [
        BoardComment(id: 'c4', author: '운영팀', body: '신고 접수되었습니다. 제보 감사합니다.', createdAt: _ago(const Duration(hours: 10)), isAdmin: true),
      ],
    ),

    // ── Q&A ──
    BoardPost(
      id: 'q1', type: BoardType.qna, isAnswered: true,
      title: '스캔이 자꾸 인식 실패해요 ㅠ',
      body: '카드를 비춰도 인식이 안 되는데 팁 있을까요?',
      author: '초보수집러', createdAt: _ago(const Duration(hours: 6)), viewCount: 142,
      comments: [
        BoardComment(id: 'a1', author: '운영팀', body: '밝은 곳에서 카드 전체가 프레임 안에 들어오게 비춰주세요. 반사광이 심하면 각도를 살짝 틀어보세요!', createdAt: _ago(const Duration(hours: 5)), isAdmin: true, isAccepted: true),
      ],
    ),
    BoardPost(
      id: 'q2', type: BoardType.qna,
      title: '예상가랑 실제 거래가가 다른 이유가 뭔가요?',
      body: '한국판 예상가라고 떠있는데 이게 어떻게 계산되는 건가요?',
      author: '궁금이', createdAt: _ago(const Duration(days: 1)), viewCount: 88,
    ),
  ];

  /// 섹션(+선택 카테고리) 필터 → 핀 우선 + 최신순.
  static List<BoardPost> bySection(BoardSection section, {BoardType? filter}) {
    final list = posts
        .where((p) =>
            section.types.contains(p.type) && (filter == null || p.type == filter))
        .toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list;
  }


  /// 상대 시간 표시.
  static String relativeTime(DateTime t) {
    final diff = _now.difference(t);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${t.month}/${t.day}';
  }
}
