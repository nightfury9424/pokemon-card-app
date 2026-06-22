import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';

/// 게시글 상세 — 본문 + 댓글/대댓글. (목업, 백엔드 승인 후 연결)
class BoardDetailScreen extends StatelessWidget {
  final BoardPost post;
  const BoardDetailScreen({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text(post.type.label,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                _header(),
                const SizedBox(height: 18),
                Text(post.body,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14.5, height: 1.6)),
                const SizedBox(height: 20),
                _reactions(),
                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.divider),
                const SizedBox(height: 16),
                _commentsHeader(),
                const SizedBox(height: 8),
                ...post.comments.map(_commentTile),
                if (post.comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: Text('첫 댓글을 남겨보세요',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13))),
                  ),
              ],
            ),
          ),
          _commentBar(context),
        ],
      ),
    );
  }

  Widget _header() {
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
                  style: TextStyle(color: post.type.color, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
        // 적응형 작성자/메타 — 넓으면 한 줄(양끝정렬), 좁거나 큰 글자면 메타가 둘째 줄로 전환.
        // 작성자·시간·조회수를 ellipsis 로 숨기지 않음(Wrap 줄바꿈으로 처리).
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
                child: Text(post.author.characters.first,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              // 닉네임만 통제불가 단일필드라 최후수단 ellipsis(point6). 시간·조회는 안 숨김.
              Flexible(
                child: Text(post.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (post.isAdmin) ...[
                const SizedBox(width: 6),
                _adminBadge(),
              ],
            ]),
            Text('${BoardMock.relativeTime(post.createdAt)} · 조회 ${post.viewCount}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ],
        ),
      ],
    );
  }

  Widget _reactions() {
    return Row(children: [
      _reactionBtn(Icons.favorite_border, '좋아요 ${post.likeCount}'),
      const SizedBox(width: 10),
      _reactionBtn(Icons.share_outlined, '공유'),
    ]);
  }

  Widget _reactionBtn(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _commentsHeader() {
    return Text('댓글 ${post.commentCount}',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700));
  }

  Widget _commentTile(BoardComment c, {bool isReply = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(isReply ? 28 : 0, 10, 0, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.isAccepted ? AppColors.green.withValues(alpha: 0.08) : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(12),
              border: c.isAccepted
                  ? Border.all(color: AppColors.green.withValues(alpha: 0.4))
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (isReply)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.subdirectory_arrow_right, size: 13, color: AppColors.textMuted),
                    ),
                  Text(c.author,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  if (c.isAdmin) ...[const SizedBox(width: 5), _adminBadge()],
                  if (c.isAccepted) ...[
                    const SizedBox(width: 5),
                    Row(mainAxisSize: MainAxisSize.min, children: const [
                      Icon(Icons.check_circle, size: 13, color: AppColors.green),
                      SizedBox(width: 2),
                      Text('채택', style: TextStyle(color: AppColors.green, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ]),
                  ],
                  const Spacer(),
                  Text(BoardMock.relativeTime(c.createdAt),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                ]),
                const SizedBox(height: 6),
                Text(c.body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
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
