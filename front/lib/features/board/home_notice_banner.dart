import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';
import 'board_screen.dart';
import 'board_detail_screen.dart';

/// 홈 카드 위 얇은 가로 공지배너 — 최신 핀 공지/이벤트 1개, 탭 → 상세 / › → 게시판.
/// (post-launch 게시판 진입점. 목업. 세로 롤링은 후속에 AnimatedSwitcher로.)
class HomeNoticeBanner extends StatelessWidget {
  const HomeNoticeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final items = BoardMock.bannerItems();
    if (items.isEmpty) return const SizedBox.shrink();
    final p = items.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => BoardDetailScreen(post: p))),
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider, width: 1),
          ),
          child: Row(
            children: [
              const Icon(Icons.campaign, size: 17, color: AppColors.blueLight),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: p.type.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(p.type.label,
                    style: TextStyle(
                        color: p.type.color, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const BoardScreen())),
                child: const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
