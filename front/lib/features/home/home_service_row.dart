import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_info_toast.dart';
import '../board/board_screen.dart';

/// 홈 서비스 바로가기 — 게시판/오리파/경매/이벤트 아이콘 허브.
/// 확장 가능: 새 기능 = _ServiceItem 1개 추가. (오리파·경매·이벤트는 준비중 placeholder)
class HomeServiceRow extends StatelessWidget {
  const HomeServiceRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 0),
      child: Row(
        children: [
          _ServiceItem(
            icon: Icons.forum_outlined,
            label: '게시판',
            color: AppColors.blue,
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const BoardScreen())),
          ),
          _ServiceItem(
            icon: Icons.auto_awesome_outlined,
            label: '오리파',
            color: const Color(0xFFB57EDC),
            onTap: () => AppInfoToast.show(context, '오리파는 곧 만나요! 🎴'),
          ),
          _ServiceItem(
            icon: Icons.gavel_outlined,
            label: '경매',
            color: AppColors.gold,
            onTap: () => AppInfoToast.show(context, '경매는 곧 만나요! 🔨'),
          ),
          _ServiceItem(
            icon: Icons.celebration_outlined,
            label: '이벤트',
            color: AppColors.green,
            onTap: () => AppInfoToast.show(context, '이벤트가 준비 중이에요 🎁'),
          ),
        ],
      ),
    );
  }
}

class _ServiceItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ServiceItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
