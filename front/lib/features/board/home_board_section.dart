import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';
import 'board_screen.dart';
import 'board_detail_screen.dart';

/// 홈 카드 아래 게시판 패널 — 공지·소식/커뮤니티/Q&A를 **하나의 통 컨테이너**로 묶음.
/// 섹션별 서브헤더(아이콘+제목+더보기) + 글 한 줄씩(앞에 타입칩). (post-launch, 목업)
class HomeBoardPanel extends StatelessWidget {
  const HomeBoardPanel({super.key});

  static IconData _iconFor(BoardSection s) {
    switch (s) {
      case BoardSection.official: return Icons.campaign_outlined;
      case BoardSection.community: return Icons.forum_outlined;
      case BoardSection.qna: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = BoardSection.values;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.dividerSoft),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int s = 0; s < sections.length; s++) ...[
              if (s > 0)
                const Divider(height: 1, thickness: 1, color: AppColors.bg),
              _Section(section: sections[s]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final BoardSection section;
  const _Section({required this.section});

  @override
  Widget build(BuildContext context) {
    final preview = section == BoardSection.community ? 3 : 2;
    final posts = BoardMock.bySection(section).take(preview).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 섹션 서브헤더 (더보기 → 게시판 해당 섹션)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => BoardScreen(initialSection: section))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 6),
            child: Row(
              children: [
                Icon(HomeBoardPanel._iconFor(section), size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 7),
                Text(section.label,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w700)),
                const Spacer(),
                const Text('더보기', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const Icon(Icons.chevron_right, size: 15, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
        for (final p in posts) _PreviewRow(post: p),
        const SizedBox(height: 8),
      ],
    );
  }
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            // 앞에 타입칩 (공지/거래후기/사기주의/Q&A...)
            Container(
              width: 54,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: post.type.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(post.type.label,
                  style: TextStyle(
                      color: post.type.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
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
                  style: const TextStyle(
                      color: AppColors.blueLight, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
