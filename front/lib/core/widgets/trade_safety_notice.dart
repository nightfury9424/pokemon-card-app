import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 거래 안전 고지 — 판매글 등록 / 구매요청 / 거래 채팅 진입 시 노출.
/// 포켓폴리오는 직거래 연결 서비스이며 거래 당사자가 아님을 고지 (App Review UGC 안전 + 분쟁 대응).
class TradeSafetyNotice extends StatelessWidget {
  final EdgeInsetsGeometry? margin;
  const TradeSafetyNotice({super.key, this.margin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider, width: 1),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, size: 16, color: AppColors.textSecondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '포켓폴리오는 이용자 간 직거래를 연결하는 서비스로, 거래 당사자가 아닙니다. 거래 전 상대방과 카드 상태를 직접 확인하세요. 분쟁 발생 시 신고·채팅·거래 상태 기록이 확인될 수 있습니다.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
