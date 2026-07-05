import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'pressable.dart';

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

/// 톤 태그 칩 — borderless tonal (bg 색 .14 + 색 텍스트). 기존 "fill+Border.all" 칩 대체.
class AppTagChip extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;
  const AppTagChip({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// 레어도 배지 — AppColors.rarityColor 단일 소스 + AppTagChip 과 동일한 tonal 스타일.
/// 빈 레어도는 렌더 안 함.
class AppRarityBadge extends StatelessWidget {
  final String rarity;
  final double fontSize;
  const AppRarityBadge(this.rarity, {super.key, this.fontSize = 10});

  @override
  Widget build(BuildContext context) {
    if (rarity.isEmpty) return const SizedBox.shrink();
    final color = AppColors.rarityColor(rarity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        rarity,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// 블랙-골드 실카드 인증 배지 — 단일 진실원 (asset 그리드 / card_detail 중복 제거).
/// 기본 = 원형(체크만), label 지정 시 = 골드 텍스트 pill. glow 없음(Toss restyle에서 제거).
/// 접근성: Tooltip 만 사용 — Tooltip.message 가 자체 Semantics 제공 (외부 Semantics 중복 금지).
class AppVerifiedGoldBadge extends StatelessWidget {
  static const _bg = Color(0xFF15110A);
  static const _gold = Color(0xFFD4AF37);
  static const _goldLight = Color(0xFFFFD86B);

  final String? tooltip;
  final String? label;
  final double size;
  const AppVerifiedGoldBadge({super.key, this.tooltip, this.label, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final Widget badge = label == null
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: _bg,
              shape: BoxShape.circle,
              border: Border.all(color: _gold, width: 1.2),
            ),
            child: Icon(Icons.check_rounded, size: size * 0.6, color: _goldLight),
          )
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(size),
              border: Border.all(color: _gold, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, size: size * 0.6, color: _goldLight),
                const SizedBox(width: 3),
                Text(
                  label!,
                  style: TextStyle(
                    color: _goldLight,
                    fontSize: size * 0.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          );
    if (tooltip == null) return badge;
    return Tooltip(message: tooltip!, child: badge);
  }
}

/// 메타 dot 행 — "좋아요 3 · 댓글 1 · 조회 12" 류. 빈 항목은 join 전에 걸러서 전달.
class AppMetaDotRow extends StatelessWidget {
  final List<String> parts;
  final TextStyle? style;
  const AppMetaDotRow(this.parts, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return Text(
      parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ??
          const TextStyle(
            color: AppColors.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
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
    return Pressable(
      onTap: onTap,
      pressedScale: 0.98,
      duration: const Duration(milliseconds: 120),
      haptic: false,
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
            ?trailing,
            if (showChevron)
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
