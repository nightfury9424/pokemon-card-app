import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'utils/hoga_format.dart';

/// 호가창 중앙 기준가 행. ASK와 BID 사이 — 코인 호가창 pivot 느낌.
class HogaPivotRow extends StatelessWidget {
  final int? marketPrice;
  final int tickUnit;

  const HogaPivotRow({
    super.key,
    required this.marketPrice,
    required this.tickUnit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            '기준가',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            marketPrice == null ? '—' : formatKrw(marketPrice!),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const Spacer(),
          Text(
            '1tick ${formatKrw(tickUnit)}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
