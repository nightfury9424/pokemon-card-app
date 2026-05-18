import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'hoga_grid_row.dart';
import 'utils/hoga_format.dart';

/// 호가창 중앙 기준가 row — ASK와 BID 사이.
///
/// HogaRow와 같은 3-column grid를 공유해 가격 column이 같은 x축에 정렬된다.
/// - 좌측: '중간가' 라벨
/// - 중앙: 큰 가격
/// - 우측: 1tick 정보
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
    return HogaGridRow(
      height: 38,
      backgroundColor: AppColors.surface,
      border: const Border(
        top: BorderSide(color: AppColors.divider, width: 1),
        bottom: BorderSide(color: AppColors.divider, width: 1),
      ),
      left: const Padding(
        padding: EdgeInsets.only(left: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: Text(
            '중간가',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
      center: Text(
        marketPrice == null ? '—' : formatKrw(marketPrice!),
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
      right: Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '1tick ${formatKrw(tickUnit)}',
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
