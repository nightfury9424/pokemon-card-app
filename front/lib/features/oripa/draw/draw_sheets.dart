import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pressable.dart';
import '../oripa_common.dart';
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

/// 결과 시트 — 보관/교환 후 다시뽑기/돌아가기. 'again' | 'back' 반환. 결과 전 dismiss 불가.
Future<String?> showDrawResultSheet(
    BuildContext context, OripaProduct o, DrawResult result) {
  return showModalBottomSheet<String>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => PopScope(
      canPop: false,
      child: _ResultSheet(oripa: o, result: result),
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

class _ResultSheet extends StatefulWidget {
  final OripaProduct oripa;
  final DrawResult result;
  const _ResultSheet({required this.oripa, required this.result});
  @override
  State<_ResultSheet> createState() => _ResultSheetState();
}

class _ResultSheetState extends State<_ResultSheet> {
  String? _done; // null | 'kept' | 'exchanged'

  @override
  Widget build(BuildContext context) {
    final p = widget.result.prize;
    final s = OripaSession.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              SizedBox(
                width: 76,
                height: 106,
                child: OripaPrizeTile(prize: p),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${widget.result.number}번 상품', style: AppText.caption),
                  const SizedBox(height: 4),
                  Text(p.displayName,
                      style: AppText.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Text('교환 ${formatPoint(p.exchangePoints)}', style: AppText.bodyStrong),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            if (_done == null)
              Row(children: [
                Expanded(
                    child: sheetButton('보관하기', filled: false, onTap: () {
                  s.keepPrize(widget.oripa.shopId, widget.result);
                  setState(() => _done = 'kept');
                })),
                const SizedBox(width: 10),
                Expanded(
                    child: sheetButton('${formatPoint(p.exchangePoints)}로 교환',
                        filled: true, onTap: () {
                  s.exchangePrize(widget.result);
                  setState(() => _done = 'exchanged');
                })),
              ])
            else ...[
              Text(
                _done == 'kept'
                    ? '${OripaMock.shopById(widget.oripa.shopId).shopName} 보관함에 보관됐어요'
                    : '${formatPoint(p.exchangePoints)}로 교환됐어요 · 현재 ${formatPoint(s.points)}',
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _againBack(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _againBack(BuildContext context) {
    final canAgain = OripaSession.instance.canDraw(widget.oripa);
    return Column(children: [
      sheetButton(
        canAgain ? '다시 뽑기 · ${formatPoint(widget.oripa.pricePerDraw)}' : '포인트가 부족합니다',
        filled: true,
        onTap: canAgain ? () => Navigator.pop(context, 'again') : null,
      ),
      const SizedBox(height: 8),
      Pressable(
        onTap: () => Navigator.pop(context, 'back'),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          child: Text('오리파로 돌아가기',
              style: AppText.body.copyWith(color: AppColors.textSecondary)),
        ),
      ),
    ]);
  }
}
