import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'models/hoga_board_model.dart';
import 'utils/hoga_format.dart';

/// 호가창 단일 행 — 가격 + count + barRatio.
///
/// 코인 거래소 스타일: 컴팩트 row, 막대는 row 배경에 옅게.
/// ASK = 파랑, BID = 초록. Red 금지.
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
      child: SizedBox(
        height: 30,
        child: Stack(
          children: [
            // 막대 (배경) — count 비율만큼 row 안쪽 채움
            Positioned.fill(
              child: Align(
                alignment: side == HogaSide.ask
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: bgRatio,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: highlight ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            // 가격 + count
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      formatKrw(level.price),
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  Text(
                    '${level.count}건',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
