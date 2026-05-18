import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'hoga_grid_row.dart';
import 'models/hoga_board_model.dart';
import 'utils/hoga_format.dart';

/// 호가창 단일 row — **토스증권식 3-column 중앙 가격축**.
///
/// 레이아웃:
/// - ASK row: 좌측 column에 count + bar(우→좌, 중앙 가격축 방향), 중앙은 가격, 우측은 빈 칸
/// - BID row: 좌측 빈 칸, 중앙은 가격, 우측 column에 count + bar(좌→우, 중앙 가격축 방향)
///
/// 색상 정책 (feedback_color_policy.md): ASK = AppColors.red, BID = AppColors.blue (한국 주식 관습).
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
    final isAsk = side == HogaSide.ask;
    // 색상 정책 (feedback_color_policy.md): 매도(위쪽)=빨강, 매수(아래쪽)=파랑.
    final color = isAsk ? AppColors.red : AppColors.blue;
    final bgRatio = level.barRatio.clamp(0.0, 1.0);

    // 중앙 가격 (모든 row 공통, x축 고정)
    final priceWidget = Text(
      formatKrw(level.price),
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: highlight ? FontWeight.w900 : FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );

    // 잔량 영역 — bar(배경) + count(텍스트). bar는 중앙 가격축 방향으로 깔림.
    final countAndBar = Stack(
      children: [
        // bar: ASK는 Align.centerRight (우→좌 방향), BID는 Align.centerLeft (좌→우)
        Positioned.fill(
          child: Align(
            alignment: isAsk ? Alignment.centerRight : Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: bgRatio,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: highlight ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
        // count: 가격에 가까운 쪽 정렬 (ASK는 우측 정렬, BID는 좌측 정렬)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(
            alignment: isAsk ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(
              '${level.count}건',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );

    return HogaGridRow(
      onTap: onTap,
      height: 32,
      left: isAsk ? countAndBar : const SizedBox.shrink(),
      center: priceWidget,
      right: isAsk ? const SizedBox.shrink() : countAndBar,
    );
  }
}
