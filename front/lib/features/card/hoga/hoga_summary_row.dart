import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import 'models/hoga_board_model.dart';
import 'utils/hoga_format.dart';

/// 호가창 상단 요약 — 최저 매도 / 최고 매수 / 스프레드 / 매도·매수 카운트.
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Item(
            label: '최저 매도',
            value: lowestAsk == null ? '—' : formatKrw(lowestAsk),
            color: AppColors.blue,
          ),
          const SizedBox(width: 14),
          _Item(
            label: '최고 매수',
            value: highestBid == null ? '—' : formatKrw(highestBid),
            color: AppColors.green,
          ),
          const SizedBox(width: 14),
          _Item(
            label: '스프레드',
            value: spread == null ? '—' : formatKrw(spread),
            color: AppColors.textSecondary,
          ),
          const Spacer(),
          Text(
            '매도 ${board.askCount} · 매수 ${board.bidCount}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Item({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
