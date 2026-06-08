import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'models/board_post.dart';
import 'data/board_mock.dart';
import 'board_screen.dart';
import 'board_detail_screen.dart';

/// 홈 카드 위 얇은 가로 공지배너 — 최신 공지/이벤트 세로 롤링, 탭 → 게시판.
/// (post-launch 게시판 진입점. 목업, 백엔드 승인 후 연결.)
class HomeNoticeBanner extends StatefulWidget {
  const HomeNoticeBanner({super.key});

  @override
  State<HomeNoticeBanner> createState() => _HomeNoticeBannerState();
}

class _HomeNoticeBannerState extends State<HomeNoticeBanner> {
  final _items = BoardMock.bannerItems();
  final _ctrl = PageController();
  Timer? _timer;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    if (_items.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        _page = (_page + 1) % _items.length;
        _ctrl.animateToPage(_page,
            duration: const Duration(milliseconds: 420), curve: Curves.easeInOut);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _openBoard() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const BoardScreen()));

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.campaign, size: 17, color: AppColors.blueLight),
            const SizedBox(width: 10),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                scrollDirection: Axis.vertical,
                physics: const NeverScrollableScrollPhysics(), // 자동 롤링만(홈 스크롤과 충돌 방지)
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final p = _items[i];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => BoardDetailScreen(post: p))),
                    child: Row(
                      children: [
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
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            GestureDetector(
              onTap: _openBoard,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
