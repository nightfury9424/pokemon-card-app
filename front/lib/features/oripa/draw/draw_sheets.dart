import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../data/oripa_mock.dart';
import '../data/oripa_session.dart';

/// 1구 뽑기 확인 시트 — [1구 뽑기] 누르면 true 반환(오터치/오버셀 가드).
Future<bool?> showDrawConfirmSheet(BuildContext context, OripaProduct o) {
  final s = OripaSession.instance;
  final after = s.points - o.pricePerDraw;
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1구를 뽑을까요?', style: AppText.h2),
            const SizedBox(height: 20),
            _amountRow('사용 포인트', '-${formatPoint(o.pricePerDraw)}'),
            const SizedBox(height: 8),
            _amountRow('현재 포인트', formatPoint(s.points)),
            const SizedBox(height: 8),
            _amountRow('뽑은 후 잔액', formatPoint(after), strong: true),
            const SizedBox(height: 16),
            Text('뽑기를 시작하면 취소할 수 없습니다.', style: AppText.muted),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: sheetButton('취소', filled: false, onTap: () => Navigator.pop(ctx, false))),
              const SizedBox(width: 10),
              Expanded(child: sheetButton('1구 뽑기', filled: true, onTap: () => Navigator.pop(ctx, true))),
            ]),
          ],
        ),
      ),
    ),
  );
}

Widget _amountRow(String label, String value, {bool strong = false}) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppText.body.copyWith(color: AppColors.textSecondary)),
        Text(value, style: strong ? AppText.bodyStrong : AppText.body),
      ],
    );

Widget sheetButton(String label,
        {required bool filled, required VoidCallback? onTap}) =>
    Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null
              ? AppColors.surfaceCard
              : (filled ? AppColors.blue : AppColors.surfaceCard),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(label,
            style: TextStyle(
                color: onTap == null
                    ? AppColors.textMuted
                    : (filled ? Colors.white : AppColors.textSecondary),
                fontSize: 15,
                fontWeight: FontWeight.w700)),
      ),
    );

// 결과 액션은 draw 화면 내부(RevealView → resultView)에서 완결(3b-2). 결과 시트 제거됨.
