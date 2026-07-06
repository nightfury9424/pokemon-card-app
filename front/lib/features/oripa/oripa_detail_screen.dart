import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import 'oripa_common.dart';
import 'data/oripa_mock.dart';

/// 오리파 상세 (STEP 1 mock) — 구수 현황 + 대표 상품 + (번호형)상품판 투명성.
/// 뽑기 CTA는 표시하되 개봉은 mock 안내만. 실제 개봉 인터랙션은 이후 단계.
class OripaDetailScreen extends StatelessWidget {
  final String oripaId;
  const OripaDetailScreen({super.key, required this.oripaId});

  @override
  Widget build(BuildContext context) {
    final o = OripaMock.oripaById(oripaId);
    final shop = OripaMock.shopById(o.shopId);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: oripaAppBar('오리파 상세'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Row(
            children: [
              AppTagChip(
                label: o.type.label,
                color:
                    o.type == OripaType.number ? AppColors.blue : AppColors.gold,
              ),
              const SizedBox(width: 8),
              Text(shop.shopName, style: AppText.caption),
            ],
          ),
          const SizedBox(height: 12),
          Text(o.title, style: AppText.h1),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${o.remainingSlots}',
                        style: AppText.h1.copyWith(color: AppColors.blueLight)),
                    Text(' / ${o.totalSlots}구 남음', style: AppText.caption),
                    const Spacer(),
                    Text('1구 ${formatPoint(o.pricePerDraw)}',
                        style: AppText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 12),
                OripaSlotBar(o.soldFraction),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const AppSectionLabel('대표 상품'),
          const SizedBox(height: 8),
          AppGroupCard(
            children: [
              for (final p in o.featuredPrizes)
                AppMenuRow(
                  icon: Icons.emoji_events_rounded,
                  color: AppColors.gold,
                  label: p,
                  showChevron: false,
                ),
            ],
          ),
          if (o.type == OripaType.number) ...[
            const SizedBox(height: 24),
            const AppSectionLabel('상품판 (번호별 현황)'),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                '뽑힌 번호는 빈자리로 남아요. 좋은 상품이 남았는지 확인하세요.',
                style: AppText.muted,
              ),
            ),
            const SizedBox(height: 12),
            _SlotBoard(total: o.totalSlots, sold: o.soldSlots),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: OripaPrimaryButton(
          label: '1구 뽑기 · ${formatPoint(o.pricePerDraw)}',
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('개봉 기능은 다음 단계에서 연결됩니다'),
              behavior: SnackBarBehavior.floating,
            ),
          ),
        ),
      ),
    );
  }
}

/// 번호 오리파 상품판 — 남은 번호는 숫자, 뽑힌 번호는 빈(dim) 자리.
class _SlotBoard extends StatelessWidget {
  final int total;
  final int sold;
  const _SlotBoard({required this.total, required this.sold});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (int n = 1; n <= total; n++) _slot(n, taken: n <= sold),
      ],
    );
  }

  Widget _slot(int n, {required bool taken}) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: taken ? AppColors.dividerSoft : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        taken ? '' : '$n',
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
