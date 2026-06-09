import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';
import 'board_screen.dart';
import 'board_detail_screen.dart';

/// 홈 카드 아래 게시판 섹션 미리보기 — 헤더(섹션명 + 더보기) + 최신 글 한 줄씩.
/// 더보기 → 게시판(해당 섹션), 글 탭 → 상세. (post-launch, 목업)
class HomeBoardSection extends StatelessWidget {
  final BoardSection section;
  const HomeBoardSection({super.key, required this.section});

  IconData get _icon {
    switch (section) {
      case BoardSection.official: return Icons.campaign_outlined;
      case BoardSection.community: return Icons.forum_outlined;
      case BoardSection.qna: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = section == BoardSection.community ? 3 : 2;
    final posts = BoardMock.bySection(section).take(preview).toList();
    if (posts.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 섹션명 + 더보기(우상단)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openBoard(context),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(_icon, size: 17, color: AppColors.textSecondary),
                  const SizedBox(width: 7),
                  Text(section.label,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const Text('더보기',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          // 글 한 줄씩
          Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.dividerSoft),
            ),
            child: Column(
              children: [
                for (int i = 0; i < posts.length; i++) ...[
                  if (i > 0) const Divider(height: 1, color: AppColors.dividerSoft, indent: 14, endIndent: 14),
                  _PreviewRow(post: posts[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openBoard(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => BoardScreen(initialSection: section)));
}

class _PreviewRow extends StatelessWidget {
  final BoardPost post;
  const _PreviewRow({required this.post});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => BoardDetailScreen(post: post))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: post.type.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(post.type.label,
                  style: TextStyle(color: post.type.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(post.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500)),
            ),
            if (post.type == BoardType.qna && post.isAnswered) ...[
              const SizedBox(width: 6),
              const Icon(Icons.check_circle, size: 14, color: AppColors.green),
            ] else if (post.commentCount > 0) ...[
              const SizedBox(width: 8),
              Text('${post.commentCount}',
                  style: const TextStyle(color: AppColors.blueLight, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(width: 8),
            Text(BoardMock.relativeTime(post.createdAt),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
