import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_state.dart';
import '../../core/theme/app_colors.dart';

/// 2026-05-29 admin Stage 0 — 관리자 홈 (3 entry).
///
/// 정책:
///   - AuthState.isAdmin false 시 home에서 자동 pop (route guard 보완).
///     ProfileScreen 의 메뉴는 이미 isAdmin 분기로 숨김.
///   - 신고 / 사용자 / 거래글 admin 삭제 3 메뉴.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 정책 위반 진입 시 즉시 뒤로 (allowlist 빠진 사용자가 직접 /admin URL 시도).
    if (!AuthState.instance.isAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.pop();
      });
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('관리자',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text(
              '운영 도구',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '신고 처리 / 사용자 관리 / 거래글 삭제.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 24),
            _AdminMenuCard(
              icon: Icons.flag_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: '신고 처리',
              subtitle: 'PENDING 신고 list / 처리 / admin memo',
              onTap: () => context.push('/admin/reports'),
            ),
            const SizedBox(height: 10),
            _AdminMenuCard(
              icon: Icons.person_search_rounded,
              iconColor: AppColors.blueLight,
              title: '사용자 검색 / 정지',
              subtitle: '닉네임 또는 이메일로 검색 → 정지/복구',
              onTap: () => context.push('/admin/users'),
            ),
            const SizedBox(height: 10),
            _AdminMenuCard(
              icon: Icons.delete_sweep_rounded,
              iconColor: AppColors.red,
              title: '거래글 admin 삭제',
              subtitle: '거래글 ID 입력 → soft delete + 양쪽 채팅방 SYSTEM 알림',
              onTap: () => context.push('/admin/trade-posts'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMenuCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AdminMenuCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11.5,
                          height: 1.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
