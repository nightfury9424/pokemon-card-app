import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import '../../core/widgets/pressable.dart';
import 'oripa_common.dart';
import 'data/oripa_mock.dart';
import 'data/oripa_session.dart';

/// 매장 상세 (STEP 2) — 진행 중 오리파 리스트. 남은 구수는 세션 기반 실시간.
class ShopDetailScreen extends StatelessWidget {
  final String shopId;
  const ShopDetailScreen({super.key, required this.shopId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OripaSession.instance,
      builder: (context, _) {
        final shop = OripaMock.shopById(shopId);
        final oripas = OripaMock.oripasByShop(shopId);
        final s = OripaSession.instance;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: oripaAppBar(shop.shopName),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Row(
                  children: [
                    const AppSquircleIcon(
                        icon: Icons.storefront_rounded,
                        color: AppColors.blue,
                        size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shop.shopName, style: AppText.title),
                          const SizedBox(height: 3),
                          Text(
                            '${shop.area} · 무료배송 기준 ${formatPoint(shop.freeShippingThreshold)}',
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const AppSectionLabel('진행 중인 오리파'),
              const SizedBox(height: 8),
              for (final o in oripas) ...[
                _OripaCard(
                  oripa: o,
                  remaining: s.remaining(o),
                  onTap: () => context.push('/oripa/detail/${o.oripaId}'),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _OripaCard extends StatelessWidget {
  final OripaProduct oripa;
  final int remaining;
  final VoidCallback onTap;
  const _OripaCard(
      {required this.oripa, required this.remaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final soldFraction =
        oripa.totalSlots == 0 ? 0.0 : 1 - remaining / oripa.totalSlots;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppTagChip(
                  label: oripa.type.label,
                  color: oripa.type == OripaType.number
                      ? AppColors.blue
                      : AppColors.gold,
                ),
                const Spacer(),
                Text('1구 ${formatPoint(oripa.pricePerDraw)}',
                    style: AppText.bodyStrong),
              ],
            ),
            const SizedBox(height: 10),
            Text(oripa.title, style: AppText.title),
            const SizedBox(height: 12),
            OripaSlotBar(soldFraction),
            const SizedBox(height: 6),
            Row(
              children: [
                Text('남은 $remaining/${oripa.totalSlots}구', style: AppText.caption),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textMuted, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
