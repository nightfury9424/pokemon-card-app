import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'models/hoga_board_model.dart';
import 'utils/hoga_format.dart';

/// 호가창 단일 행 — 가격 + 등록 건수 + 잔량 막대(barRatio).
///
/// 색상: ASK=파랑(좌측 정렬), BID=초록(우측 정렬). Red 금지.
class HogaRow extends StatelessWidget {
  final HogaLevel level;
  final HogaSide side;
  final bool highlight;
  final VoidCallback? onTap;

  const HogaRow({
    super.key,
    required this.level,
    required this.side,
    this.highlight = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = side == HogaSide.ask ? AppColors.blue : AppColors.green;
    final bgRatio = level.barRatio.clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: highlight ? color.withValues(alpha: 0.05) : null,
          border: Border(
            bottom: BorderSide(color: AppColors.dividerSoft, width: 0.5),
          ),
        ),
        child: Stack(
          children: [
            // 잔량 막대 (배경)
            Positioned.fill(
              child: Align(
                alignment: side == HogaSide.ask
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: bgRatio,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            // 가격 + count
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatKrw(level.price),
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${level.count}건',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
