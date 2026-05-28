import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'models/hoga_board_model.dart';
import 'utils/hoga_format.dart';

/// 호가창 상단 한 줄 요약 — 박스 없이 inline.
class HogaSummaryRow extends StatelessWidget {
  final HogaBoardData board;

  const HogaSummaryRow({super.key, required this.board});

  @override
  Widget build(BuildContext context) {
    final lowestAsk = board.lowestAsk;
    final highestBid = board.highestBid;
    int? spread;
    if (lowestAsk != null && highestBid != null) {
      spread = lowestAsk - highestBid;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        child: Row(
          children: [
            _label('최저매도'),
            const SizedBox(width: 4),
            // 색상 정책 (feedback_color_policy.md, 2026-05-28 정정): 매도=파랑, 매수=빨강.
            Text(
              lowestAsk == null ? '—' : formatKrw(lowestAsk),
              style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 12),
            _label('최고매수'),
            const SizedBox(width: 4),
            Text(
              highestBid == null ? '—' : formatKrw(highestBid),
              style: const TextStyle(color: AppColors.red, fontSize: 11, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 12),
            _label('스프레드'),
            const SizedBox(width: 4),
            Text(
              spread == null ? '—' : formatKrw(spread),
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '매도 ${board.askCount} · 매수 ${board.bidCount}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Text(
        s,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
      );
}
