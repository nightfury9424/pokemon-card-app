import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 손익 표시 — text-only가 아니라 delta arrow + pill로 시각화.
/// + 상승 / − 하락 / · 변동 없음.
/// REFACTOR_2026-05-12.md 4차-Round1 디자인 polish.
class DeltaPill extends StatelessWidget {
  final num? amount;    // 변동 금액 (양수=상승, 음수=하락, null=숨김)
  final double? percent; // 변동 %
  final String Function(num) amountFormatter;
  final bool compact;    // true면 % 만 (좁은 영역용)
  final double fontSize;

  const DeltaPill({
    super.key,
    required this.amount,
    required this.percent,
    required this.amountFormatter,
    this.compact = false,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    if (amount == null || percent == null) return const SizedBox.shrink();
    final isUp = amount! > 0;
    final isFlat = amount! == 0;
    final color = isFlat
        ? AppColors.textSecondary
        : (isUp ? AppColors.green : AppColors.red);
    final icon = isFlat
        ? Icons.remove_rounded
        : (isUp ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded);

    final pctText = '${percent!.abs().toStringAsFixed(1)}%';
    final amtText = amountFormatter(amount!.abs());

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.sm : AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.32), width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: fontSize + 4),
          if (!compact) ...[
            const SizedBox(width: 2),
            Text(
              amtText,
              style: TextStyle(
                color: color,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              '  ·  ',
              style: TextStyle(color: color.withValues(alpha: 0.4), fontSize: fontSize),
            ),
          ],
          Text(
            pctText,
            style: TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
