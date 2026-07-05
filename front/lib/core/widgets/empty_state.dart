import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'app_list_ui.dart';
import 'pressable.dart';

/// 빈 상태 — 입체 스쿼클 아이콘(앱 시그니처) + 텍스트 + pill CTA. (Toss restyle 2026-07)
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
    final accent = accentColor ?? AppColors.blue;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSquircleIcon(icon: icon, color: accent, size: 56),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ],
            if (ctaLabel != null && onCta != null) ...[
              const SizedBox(height: 20),
              Pressable(
                onTap: onCta,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    ctaLabel!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
