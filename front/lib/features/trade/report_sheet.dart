import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';

/// 공용 신고 시트 — 판매글/구매글/채팅 공통. 단일 토스 스타일 시트
/// (경고 박스 + 사유 선택 + 상세 입력 + 신고 접수)로 디자인 통일.
/// 기존 trade_detail 의 "사유 sheet → 상세 AlertDialog" 2단계(디자인 불일치) 대체.
class ReportSheet {
  static const List<Map<String, String>> _defaultReasons = [
    {'code': 'FRAUD', 'label': '사기 의심', 'desc': '입금 유도 후 잠적, 허위 매물 등'},
    {'code': 'ABUSIVE_PRICE', 'label': '시세 교란', 'desc': '비정상적 가격으로 시장 교란'},
    {'code': 'INSULT', 'label': '욕설 / 비방', 'desc': '부적절한 언행'},
    {'code': 'SPAM', 'label': '스팸 / 광고', 'desc': '도배, 광고성 글'},
    {'code': 'OTHER', 'label': '기타', 'desc': '직접 사유 입력'},
  ];

  /// [targetType] TRADE / BUY_ORDER / USER / CHAT
  /// [targetNoun] 경고 문구 주어 (예: '판매자', '구매자', '사용자')
  /// [autoBlock] true 면 "신고 시 자동 차단" 문구 노출(백엔드 resolveBlockTarget 지원: TRADE/USER/CHAT).
  /// BUY_ORDER 는 현재 백엔드 자동차단 미지원 → false (문구 정확성). 자동차단 백엔드 지원은 1.0.1.
  /// 반환: 신고 제출 성공 시 true, 취소/닫기 시 false (호출부가 후속 갱신 판단 — 기존 fire-and-forget 호출은 무영향).
  static Future<bool> show(
    BuildContext context, {
    required String targetType,
    required String targetId,
    String targetNoun = '사용자',
    List<Map<String, String>>? reasons,
    bool autoBlock = true,
  }) async {
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ReportSheetBody(
          targetType: targetType,
          targetId: targetId,
          targetNoun: targetNoun,
          reasons: reasons ?? _defaultReasons,
          autoBlock: autoBlock,
        ),
      ),
    );
    return submitted ?? false; // 제출 성공(pop(true))=true, 취소/배경탭/닫기(null)=false
  }
}

class _ReportSheetBody extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String targetNoun;
  final List<Map<String, String>> reasons;
  final bool autoBlock;
  const _ReportSheetBody({
    required this.targetType,
    required this.targetId,
    required this.targetNoun,
    required this.reasons,
    required this.autoBlock,
  });

  @override
  State<_ReportSheetBody> createState() => _ReportSheetBodyState();
}

class _ReportSheetBodyState extends State<_ReportSheetBody> {
  String? _reasonCode;
  final _detail = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reasonCode == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/api/reports', {
        'data': {
          'targetType': widget.targetType,
          'targetId': widget.targetId,
          'reason': _reasonCode,
          'detail': _detail.text.trim(),
        },
      });
      if (!mounted) return;
      if (res['status'] != 'success') {
        setState(() => _submitting = false);
        AppErrorToast.show(context, res['message']?.toString() ?? '신고 접수에 실패했어요.');
        return;
      }
      Navigator.of(context).pop(true); // ★제출 성공 신호(호출부가 후속 갱신 판단)
      AppSuccessToast.show(context, '신고가 접수되었습니다');
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      AppErrorToast.show(context, '신고 접수에 실패했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('신고하기',
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.gold, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.autoBlock
                          ? '신고하면 해당 ${widget.targetNoun}가 자동으로 차단됩니다. 차단은 해제할 수 있지만 접수된 신고는 취소되지 않아요.\n'
                              '신중하게 신고해 주세요. 허위·악의적 신고는 이용 제재 대상이 될 수 있습니다.'
                          : '접수된 신고는 취소되지 않으며, 검토 후 처리됩니다.\n'
                              '신중하게 신고해 주세요. 허위·악의적 신고는 이용 제재 대상이 될 수 있습니다.',
                      style: TextStyle(
                          color: AppColors.gold.withValues(alpha: 0.95),
                          fontSize: 12,
                          height: 1.45,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('신고 사유',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...widget.reasons.map((r) {
              final selected = _reasonCode == r['code'];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _reasonCode = r['code']),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.blue.withValues(alpha: 0.12) : AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected ? AppColors.blue : AppColors.divider,
                        width: selected ? 1.4 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['label']!,
                                style: TextStyle(
                                    color: selected ? AppColors.blue : AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(r['desc']!,
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: selected ? AppColors.blue : AppColors.textMuted,
                        size: 20,
                      ),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              controller: _detail,
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: '상세 내용을 입력해 주세요 (선택)',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                filled: true,
                fillColor: AppColors.surface,
                counterStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                contentPadding: const EdgeInsets.all(14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.blue),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_reasonCode == null || _submitting) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  disabledBackgroundColor: AppColors.surface,
                  disabledForegroundColor: AppColors.textMuted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('신고 접수',
                        style: TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
