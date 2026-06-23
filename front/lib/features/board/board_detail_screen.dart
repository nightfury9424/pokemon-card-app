import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import 'models/board_post.dart';
import 'data/board_repository.dart';

/// 게시글 상세 — postId 로 상세 API 재조회(목록 summary 재사용 X).
/// 공지(official: notice/event/patch) = 본문만 읽기(댓글·반응 UI 없음).
/// 자유(free) = 본문 + 댓글·1단 대댓글 읽기(작성/좋아요 동작은 다음 슬라이스).
class BoardDetailScreen extends StatefulWidget {
  final String postId;
  final BoardRepository repository;

  /// 목록에서 넘어올 때 로딩 중 AppBar 제목 등 표시용(최종 데이터는 fetchDetail).
  final BoardPost? summary;

  const BoardDetailScreen({
    super.key,
    required this.postId,
    this.repository = const BoardRepository(),
    this.summary,
  });

  @override
  State<BoardDetailScreen> createState() => _BoardDetailScreenState();
}

class _BoardDetailScreenState extends State<BoardDetailScreen> {
  BoardPost? _post;
  bool _loading = true;
  bool _notFound = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
      _error = null;
    });
    try {
      final p = await widget.repository.fetchDetail(widget.postId);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (p == null) {
          _notFound = true; // 404 = 삭제/숨김/미존재
        } else {
          _post = p;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleType = (_post ?? widget.summary)?.type;
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(titleType?.label ?? '게시글',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.4));
    }
    if (_notFound) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('삭제되었거나 존재하지 않는 글이에요.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
        ),
      );
    }
    if (_error != null || _post == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('글을 불러오지 못했어요.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _load,
              child: const Text('다시 시도',
                  style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    }

    final post = _post!;
    final isOfficial = post.isAdmin; // notice/event/patch = 관리자 공지계열

    // 공지 = 본문만(댓글·반응·입력 없음). 자유 = 본문 + 댓글 트리 + 입력바(동작은 다음 슬라이스).
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        _header(post),
        const SizedBox(height: 18),
        Text(post.body,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, height: 1.6)),
        if (!isOfficial) ...[
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),
          Text('댓글 ${post.commentCount}',
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...post.comments.map(_commentTile),
          if (post.comments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                  child: Text('아직 댓글이 없어요',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
            ),
        ],
      ],
    );

    if (isOfficial) return content;
    return Column(children: [Expanded(child: content), _commentBar(context)]);
  }

  Widget _header(BoardPost post) {
    // 작성자 이니셜 — 빈 author(서버 라벨 누락)에도 .characters.first 가 throw 하지 않도록 가드.
    final initial = post.author.isEmpty ? '?' : post.author.characters.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: post.type.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(post.type.icon, size: 13, color: post.type.color),
              const SizedBox(width: 5),
              Text(post.type.label,
                  style: TextStyle(
                      color: post.type.color, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (post.isPinned) ...[
            const SizedBox(width: 7),
            const Icon(Icons.push_pin, size: 14, color: AppColors.gold),
          ],
        ]),
        const SizedBox(height: 12),
        Text(post.title,
            style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800, height: 1.3)),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.surfaceElevated,
                child: Text(initial,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (post.isAdmin) ...[const SizedBox(width: 6), _adminBadge()],
            ]),
            // 조회수는 0이면 숨김(증가 기능 전이라 '조회 0' 반복 노출 방지).
            Text(
              post.viewCount > 0
                  ? '${boardRelativeTime(post.createdAt)} · 조회 ${post.viewCount}'
                  : boardRelativeTime(post.createdAt),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
            ),
          ],
        ),
      ],
    );
  }

  // 1단 대댓글 읽기 표시. Q&A 채택 UI 는 1.0.4 미노출(데이터는 파싱 유지).
  Widget _commentTile(BoardComment c, {bool isReply = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 28 : 0, 10, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isReply)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.subdirectory_arrow_right,
                          size: 13, color: AppColors.textMuted),
                    ),
                  Flexible(
                    child: Text(c.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                  if (c.isAdmin) ...[const SizedBox(width: 5), _adminBadge()],
                  const SizedBox(width: 8),
                  Text(boardRelativeTime(c.createdAt),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                ]),
                const SizedBox(height: 6),
                Text(c.body,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
              ],
            ),
          ),
          ...c.replies.map((r) => _commentTile(r, isReply: true)),
        ],
      ),
    );
  }

  Widget _adminBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text('운영',
          style: TextStyle(color: AppColors.blueLight, fontSize: 9.5, fontWeight: FontWeight.w800)),
    );
  }

  Widget _commentBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.dividerSoft)),
        ),
        child: Row(children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.surfaceCard,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text('댓글을 입력하세요',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => AppInfoToast.show(context, '댓글 기능은 다음 단계에서 추가돼요'),
            child: Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
            ),
          ),
        ]),
      ),
    );
  }
}
