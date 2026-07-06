import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_list_ui.dart';
import 'oripa_common.dart';
import 'data/oripa_mock.dart';

/// 매장 목록 (STEP 1 mock) — 입점 매장 + 진행 중 오리파 수.
class ShopListScreen extends StatelessWidget {
  const ShopListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: oripaAppBar('오리파 매장'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          const AppSectionLabel('입점 매장'),
          const SizedBox(height: 8),
          AppGroupCard(
            children: [
              for (final s in OripaMock.shops)
                AppMenuRow(
                  icon: Icons.storefront_rounded,
                  color: AppColors.blue,
                  label: s.shopName,
                  subtitle:
                      '${s.area} · 진행 중 ${OripaMock.activeOripaCount(s.shopId)}개',
                  onTap: () => context.push('/oripa/shop/${s.shopId}'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
