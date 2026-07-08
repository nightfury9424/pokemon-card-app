import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import '../../core/widgets/pressable.dart';
import 'oripa_common.dart';
import 'data/oripa_mock.dart';
import 'data/oripa_session.dart';

/// 오리파 독립 홈 (STEP 2) — 세션 반응형: 포인트/보관함 실시간(교환·보관 반영).
class OripaHomeScreen extends StatelessWidget {
  const OripaHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: OripaSession.instance,
      builder: (context, _) {
        final s = OripaSession.instance;
        final shopsWithHeld = s.shopsWithHeld;
        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(context)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _pointCard(context, s.points),
                        const SizedBox(height: 28),
                        Row(children: [
                          const AppSectionLabel('내 보관함'),
                          const Spacer(),
                          Text('${s.heldTotalCount}개', style: AppText.caption),
                        ]),
                        const SizedBox(height: 8),
                        AppGroupCard(
                          children: [
                            for (final shop in shopsWithHeld)
                              AppMenuRow(
                                icon: Icons.storefront_rounded,
                                color: AppColors.blue,
                                label: shop.shopName,
                                subtitle: shop.freeShippingReached
                                    ? '무료배송 가능'
                                    : '무료배송까지 ${formatPoint(shop.shippingRemaining)}',
                                trailingText:
                                    '${s.heldByShop(shop.shopId).length}개',
                                showChevron: false,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Padding(
                          padding: EdgeInsets.only(left: 4),
                          child: Text(
                            '보관 상품은 매장별로 모아 무료배송 기준을 채우면 함께 배송해요.',
                            style: AppText.muted,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _goCta(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              ScaffoldMessenger.of(context).clearSnackBars();
              Navigator.of(context).maybePop();
            },
          ),
          const Text('오리파', style: AppText.h1),
          const SizedBox(width: 8),
          const AppTagChip(label: 'beta', color: AppColors.blueLight),
        ],
      ),
    );
  }

  Widget _pointCard(BuildContext context, int points) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('내 포인트', style: AppText.caption),
          const SizedBox(height: 8),
          Text(formatPoint(points), style: AppText.display),
          const SizedBox(height: 16),
          Pressable(
            onTap: () => oripaComingSoon(context, '포인트 충전은 준비 중입니다'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.blueDeep,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Text(
                '포인트 충전',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _goCta(BuildContext context) {
    return Pressable(
      onTap: () {
        ScaffoldMessenger.of(context).clearSnackBars();
        context.push('/oripa/shops');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '오리파 하러가기',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '· 진행 중 ${OripaMock.activeOripaTotal}개',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
