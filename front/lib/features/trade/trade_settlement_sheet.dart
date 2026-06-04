import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_segmented_toggle.dart';
import '../../core/widgets/app_success_toast.dart';

/// 천단위 콤마 포맷 (1000 → 1,000). B2-6.
String _commaFmt(int n) => n.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

/// 입력 중 천단위 콤마 자동 삽입.
class _ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final formatted = _commaFmt(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// 실거래가 입력 시트 — 거래 완료 후 양쪽 당사자가 실제 거래 금액 기입.
///
/// 정책 (2026-06-04):
/// - 원래 거래가(판매가)를 prefill → "이 금액이 맞아요" 토글이면 그대로, 다르면 "직접 입력"으로 수정.
/// - 토글은 앱 공통 [AppSegmentedToggle] 재사용.
/// - 소프트: '나중에'로 닫기 가능(인터셉터가 다음 진입 때 다시 권유). 시세 반영은 후속(수집만).
class TradeSettlementSheet extends StatefulWidget {
  // B2-12: SALE='/api/trades/{tradeId}/settlement', BUY='/api/trades/buy-order/{buyOrderId}/settlement'
  final String submitPath;
  final String? tradeTitle;
  final int? agreedPrice;
  final int? prefillPrice; // 이미 입력한 값이 있으면 그걸로 prefill

  const TradeSettlementSheet({
    super.key,
    required this.submitPath,
    this.tradeTitle,
    this.agreedPrice,
    this.prefillPrice,
  });

  /// 모달 표시. true = 입력 완료, false/null = 나중에(소프트 닫기).
  static Future<bool?> show(
    BuildContext context, {
    required String submitPath,
    String? tradeTitle,
    int? agreedPrice,
    int? prefillPrice,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => TradeSettlementSheet(
        submitPath: submitPath,
        tradeTitle: tradeTitle,
        agreedPrice: agreedPrice,
        prefillPrice: prefillPrice,
      ),
    );
  }

  @override
  State<TradeSettlementSheet> createState() => _TradeSettlementSheetState();
}

class _TradeSettlementSheetState extends State<TradeSettlementSheet> {
  late int _mode; // 0 = 거래가 그대로(맞아요), 1 = 직접 입력
  late final TextEditingController _priceCtrl;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.prefillPrice ?? widget.agreedPrice;
    // 직접 입력으로 시작하는 경우: ① 이미 입력값이 원래 거래가와 다름,
    // ② 희망가(agreedPrice) 미상 — '이 금액이 맞아요'는 빈 readonly라 진행 불가하므로.
    _mode = (widget.agreedPrice == null ||
            (widget.prefillPrice != null && widget.prefillPrice != widget.agreedPrice))
        ? 1
        : 0;
    _priceCtrl = TextEditingController(text: initial != null ? _commaFmt(initial) : '');
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  int? get _effectivePrice {
    if (_mode == 0) return widget.agreedPrice;
    final raw = _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return raw.isEmpty ? null : int.tryParse(raw);
  }

  /// B3-1: 실거래가 단위 검증(프론트 즉시 피드백). 시세 대비 밴드는 **백엔드가 최종 판정**.
  /// (희망가만으로 밴드 잡으면 희망가≪시세 카드에서 정상값을 false-positive 차단 → Codex 지적. 제거.)
  /// reference = 희망가(agreedPrice): 정확히 일치하면("이 금액이 맞아요") 100원 단위 예외.
  String? _validatePrice(int? price, int? reference) {
    if (price == null) return '거래 금액을 입력해주세요.';
    if (price < 1000) return '거래 금액은 1,000원 이상 입력해주세요.';
    if (price > 1000000000) return '금액이 올바르지 않습니다.';
    final trusted = reference != null && price == reference;
    if (!trusted && price % 100 != 0) return '거래 금액은 100원 단위로 입력해주세요.';
    return null;
  }

  Future<void> _submit() async {
    final price = _effectivePrice;
    final err = _validatePrice(price, widget.agreedPrice);
    if (err != null) {
      AppErrorToast.show(context, err);
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post(
        widget.submitPath,
        {'data': {'price': price}},
      );
      if (!mounted) return;
      // badRequest 는 HTTP 200 바디(status=fail)로 내려옴 → 시세 밴드 등 백엔드 거부 메시지 노출.
      if (res['status'] != 'success') {
        setState(() => _submitting = false);
        final msg = (res['message'] is String &&
                (res['message'] as String).trim().isNotEmpty)
            ? res['message'] as String
            : '기록에 실패했어요. 금액을 다시 확인해주세요.';
        AppErrorToast.show(context, msg);
        return;
      }
      Navigator.pop(context, true);
      AppSuccessToast.show(context, '실거래 금액이 기록됐어요. 감사합니다!');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppErrorToast.show(context, '기록에 실패했어요. 잠시 후 다시 시도해주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final readOnly = _mode == 0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 14, 20, MediaQuery.of(context).padding.bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            const Text('실제 거래 금액을 알려주세요',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              widget.tradeTitle != null && widget.tradeTitle!.isNotEmpty
                  ? '${widget.tradeTitle}\n실거래가는 시세 정확도에만 쓰여요. 맞으면 그대로, 다르면 직접 입력해주세요.'
                  : '실거래가는 시세 정확도에만 쓰여요. 원래 금액이 맞으면 그대로, 다르면 직접 입력해주세요.',
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 18),
            AppSegmentedToggle(
              labels: const ['이 금액이 맞아요', '직접 입력'],
              selectedIndex: _mode,
              onChanged: (i) => setState(() {
                _mode = i;
                if (i == 0 && widget.agreedPrice != null) {
                  _priceCtrl.text = _commaFmt(widget.agreedPrice!);
                }
              }),
            ),
            const SizedBox(height: 14),
            // 금액 입력 — mode 0 이면 원래 거래가 readOnly, mode 1 이면 직접 수정.
            TextField(
              controller: _priceCtrl,
              readOnly: readOnly,
              keyboardType: TextInputType.number,
              inputFormatters: [_ThousandsInputFormatter()],
              style: TextStyle(
                color: readOnly ? AppColors.textSecondary : AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: '예: 77000',
                hintStyle:
                    const TextStyle(color: AppColors.textMuted, fontSize: 15),
                suffixText: '원',
                suffixStyle: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700),
                filled: true,
                fillColor: readOnly
                    ? AppColors.surfaceCard
                    : AppColors.surfaceElevated,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed:
                          _submitting ? null : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('나중에',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.blue,
                        disabledBackgroundColor: AppColors.divider,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('기록하기',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                    ),
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
