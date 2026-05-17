import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 도메인 비주얼 — 그래픽 일러스트 없이도 Codex가 권한 "어두운 카드 실루엣" 분위기.
/// 카드 뒷면 실루엣 + 텍스트 + CTA 조합. (REFACTOR_2026-05-12.md 4차-Round2)
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? ctaLabel;
  final VoidCallback? onCta;
  final Color? accentColor;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.ctaLabel,
    this.onCta,
    this.accentColor,
  });

  /// 자산 0개일 때
  factory EmptyState.noAssets({VoidCallback? onAdd}) => EmptyState(
        icon: Icons.style_outlined,
        title: '아직 보유한 카드가 없어요',
        description: '스캔이나 검색으로 첫 카드를 추가하면\n실시간 시세와 손익이 자동으로 추적돼요.',
        ctaLabel: '카드 추가',
        onCta: onAdd,
        accentColor: AppColors.blue,
      );

  /// API 실패
  factory EmptyState.networkError({VoidCallback? onRetry}) => EmptyState(
        icon: Icons.wifi_off_rounded,
        title: '연결이 잠시 끊겼어요',
        description: '네트워크 상태를 확인하고\n다시 시도해주세요.',
        ctaLabel: '다시 시도',
        onCta: onRetry,
        accentColor: AppColors.red,
      );

  /// 검색 결과 0건
  factory EmptyState.noSearchResult(String keyword) => EmptyState(
        icon: Icons.search_off_rounded,
        title: '"$keyword" 결과가 없어요',
        description: '카드 이름이나 번호를 다시 입력해보세요.',
      );

  /// 시세 정보 없음
  factory EmptyState.noPriceData() => const EmptyState(
        icon: Icons.show_chart_rounded,
        title: '시세 정보 없음',
        description: '아직 거래 데이터가 수집되지 않은 카드예요.\n곧 자동으로 채워질 예정입니다.',
      );

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? AppColors.textSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 어두운 원 안에 큰 아이콘 (카드 backside 실루엣 느낌)
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.surfaceElevated,
                    AppColors.surfaceCard,
                  ],
                ),
                border: Border.all(color: AppColors.divider, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.08),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: 40,
                color: accent.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.h2.copyWith(fontWeight: FontWeight.w800),
            ),
            if (description != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.55,
                ),
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: AppSpacing.xl),
              GestureDetector(
                onTap: onCta,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: AppShadows.glow(accent),
                  ),
                  child: Text(
                    ctaLabel!,
                    style: AppText.bodyStrong.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
