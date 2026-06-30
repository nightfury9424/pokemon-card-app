import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_info_toast.dart';
import '../auth/auth_service.dart';

/// 설정 화면 — MY 탭 우상단 ⚙️ 진입.
/// 잡다한 설정·계정류(알림/차단/약관/개인정보/앱정보/로그아웃/탈퇴)를 MY 본문에서 분리.
/// 로그아웃/탈퇴 로직은 기존 profile_screen 에서 이관 — 동작 동일.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: '로그아웃',
      message: '로그아웃 하시겠습니까?',
      confirmLabel: '로그아웃',
      destructive: true,
    );
    if (confirm == true && context.mounted) {
      await AuthService.logout();
      if (context.mounted) context.go('/login');
    }
  }

  /// 계정 탈퇴. App Review 5.1.1 대응. docs/DELETION_POLICY.md 참조.
  /// 흐름: confirm → DELETE /api/users/me → AuthService.logout → /login redirect.
  /// 백엔드는 PII 마스킹 + OPEN 매수/매도 자동 취소. 거래/채팅/신고/차단 기록은 보존.
  Future<void> _deleteAccount(BuildContext context) async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: '정말 탈퇴하시겠어요?',
      message:
          '거래/채팅 기록은 분쟁 대응을 위해 보존되며 다른 사용자에게는 "탈퇴한 사용자"로 표시됩니다. '
          '진행 중인 매수/매도 호가는 자동 취소되고, 계정은 복구할 수 없어요.\n\n'
          '인증한 전화번호와 계정은 탈퇴 후 3개월간 동일 정보로 재가입할 수 없어요.',
      confirmLabel: '탈퇴하기',
      destructive: true,
    );
    if (confirm != true || !context.mounted) return;
    try {
      final res = await ApiClient.delete('/api/users/me');
      // 백엔드 envelope 체크 (HTTP 200 + {status:'fail'} 패턴 대응)
      if (res['status'] != 'success') {
        if (!context.mounted) return;
        AppInfoToast.show(context,
            res['message']?.toString() ?? '탈퇴 처리에 실패했어요. 잠시 후 다시 시도해주세요.');
        return;
      }
      await AuthService.logout();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      AppInfoToast.show(context, '탈퇴 처리에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  void _showAppInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('PokeFolio',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('v1.0.0',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            SizedBox(height: 6),
            Text('© 2026 PokeFolio',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            SizedBox(height: 12),
            Text(
                '본 앱은 비공식 팬 서비스입니다. ‘Pokémon’ 및 관련 명칭·이미지의 저작권·상표권은 각 권리자에게 있습니다.',
                style: TextStyle(
                    color: AppColors.textMuted, fontSize: 11.5, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              showLicensePage(
                context: context,
                applicationName: 'PokeFolio',
                applicationVersion: 'v1.0.0',
                applicationLegalese: '© 2026 PokeFolio',
              );
            },
            child: const Text('오픈소스 라이선스',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('닫기', style: TextStyle(color: AppColors.blue)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        title: const Text('설정',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _group([
            const _SettingsItem(
              icon: Icons.notifications_none_rounded,
              iconColor: AppColors.textMuted,
              label: '알림',
              // 알림 설정 백엔드/화면 미구현 — 준비중 disabled.
              comingSoon: true,
            ),
            _SettingsItem(
              icon: Icons.person_off_rounded,
              iconColor: AppColors.textSecondary,
              label: '차단한 사용자',
              onTap: () => context.push('/profile/blocked-users'),
            ),
          ]),
          const SizedBox(height: 20),
          _group([
            _SettingsItem(
              icon: Icons.description_outlined,
              iconColor: AppColors.textSecondary,
              label: '이용약관',
              onTap: () => context.push('/legal/terms'),
            ),
            _SettingsItem(
              icon: Icons.privacy_tip_outlined,
              iconColor: AppColors.textSecondary,
              label: '개인정보처리방침',
              onTap: () => context.push('/legal/privacy'),
            ),
            _SettingsItem(
              icon: Icons.info_outline_rounded,
              iconColor: AppColors.textMuted,
              label: '앱 정보',
              sub: 'v1.0.0',
              onTap: () => _showAppInfo(context),
            ),
          ]),
          const SizedBox(height: 20),
          // 로그아웃/탈퇴 — Apple 5.1.1(v) 인앱 계정삭제 접근성 위해 설정 본문에 명시 노출.
          _group([
            _SettingsItem(
              icon: Icons.logout_rounded,
              iconColor: AppColors.red,
              label: '로그아웃',
              labelColor: AppColors.red,
              onTap: () => _logout(context),
            ),
            _SettingsItem(
              icon: Icons.delete_forever_outlined,
              iconColor: AppColors.red,
              label: '회원탈퇴',
              labelColor: AppColors.red,
              onTap: () => _deleteAccount(context),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _group(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          return _SettingsRow(item: items[i], isLast: i == items.length - 1);
        }),
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final String? sub;
  final bool comingSoon;
  final VoidCallback? onTap;

  const _SettingsItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.sub,
    this.comingSoon = false,
    this.onTap,
  });
}

class _SettingsRow extends StatelessWidget {
  final _SettingsItem item;
  final bool isLast;

  const _SettingsRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final disabled = item.comingSoon || item.onTap == null;
    return GestureDetector(
      onTap: disabled ? null : item.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          color: item.labelColor ?? AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (item.sub != null) ...[
                        const SizedBox(height: 2),
                        Text(item.sub!,
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ],
                  ),
                ),
                if (item.comingSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('준비중',
                        style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  )
                else if (item.onTap != null)
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textMuted, size: 18),
              ],
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 66),
              child: Container(height: 0.5, color: AppColors.divider),
            ),
        ],
      ),
    );
  }
}
