import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// ★Toss restyle 공용 UI 킷 (2026-07-04) — MY 화면에서 검증된 디자인 언어.
/// 전 화면 통일의 단일 진실원: 그룹 카드 + 메뉴 행 + 입체 스쿼클 아이콘 + 섹션 라벨.
/// 새 화면/기존 화면 개편 시 개별 Container 조립 금지 — 반드시 이 부품 사용.

/// 섹션 라벨 — 13 w600 secondary.
class AppSectionLabel extends StatelessWidget {
  final String label;
  const AppSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

/// 그룹 카드 — 행들을 한 카드(surfaceCard, r16)에 묶고 인셋 디바이더로 구분.
class AppGroupCard extends StatelessWidget {
  final List<Widget> children;
  final double dividerIndent;
  const AppGroupCard({super.key, required this.children, this.dividerIndent = 64});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: dividerIndent),
          child: const Divider(height: 1, thickness: 1, color: AppColors.dividerSoft),
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// 입체 스쿼클 아이콘 — 위 밝음→아래 딥 그라데이션 + 상단 하이라이트 (pseudo-3D).
class AppSquircleIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const AppSquircleIcon({super.key, required this.icon, required this.color, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.31),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(color, Colors.white, 0.22)!,
            color,
            Color.lerp(color, Colors.black, 0.28)!,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.53),
    );
  }
}

/// 메뉴 행 — [입체 아이콘] 라벨 (서브타이틀) ··· (값/배지) chevron. 행 높이 ~56.
class AppMenuRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String? subtitle;
  final String? trailingText;
  final int? badgeCount;
  final Widget? trailing;
  final bool showChevron;
  final VoidCallback? onTap;

  const AppMenuRow({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    this.subtitle,
    this.trailingText,
    this.badgeCount,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = (badgeCount ?? 0) > 0;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AppSquircleIcon(icon: icon, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (showBadge) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                height: 20,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  badgeCount! > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (trailing != null) trailing!,
            if (showChevron)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
