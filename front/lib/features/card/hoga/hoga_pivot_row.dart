import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'utils/hoga_format.dart';

/// 호가창 중앙 기준가 행. ASK와 BID 사이.
///
/// 1차 기준가 = backend marketPrice (mid(lowestAsk, highestBid) fallback).
/// 추후 KO 추정가로 교체 예정 (CODEX_PLAN.md TODO).
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 1),
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Text(
            '기준가',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(width: 10),
          Text(
            marketPrice == null ? '—' : formatKrw(marketPrice!),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            '1tick ${formatKrw(tickUnit)}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
          ),
        ],
      ),
    );
  }
}
