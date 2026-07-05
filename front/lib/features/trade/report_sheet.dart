import 'dart:async';

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
      isDismissible: false, // 배경 탭 닫기 차단 — 제출 중 닫혀 갱신 누락되는 경로 제거(닫기는 X 버튼·뒤로로만)
      enableDrag: false, // 아래로 드래그 닫기 차단(동일)
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
  final _detailFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _scrollTimer;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // 입력창 포커스(키보드 오픈) 시에만 하단(입력 영역+글자수+신고 버튼)이 키보드 위에 보이도록 스크롤.
    // 사유 카드 선택만으로는 포커스가 안 잡혀 불필요한 점프가 없다.
    _detailFocus.addListener(_scrollToInputOnFocus);
  }

  void _scrollToInputOnFocus() {
    if (!_detailFocus.hasFocus) return;
    // 키보드 애니메이션 + viewInsets 반영(레이아웃 리플로우) 후 실제 콘텐츠 끝까지 스크롤(고정 padding 아님).
    // dispose 시 취소되는 Timer — 위젯이 닫혀도 pending 타이머가 남지 않게.
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _detailFocus.dispose();
    _scroll.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reasonCode == null || _submitting) return;
    if (_reasonCode == 'OTHER' && _detail.text.trim().isEmpty) return; // 기타=직접 사유 필수
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/api/reports', {
        'data': {
          'targetType': widget.targetType,
          'targetId': widget.targetId,
          'reason': _reasonCode,
          // 빈칸이면 null(OTHER 외 불필요 detail 미전송 — 사유 변경 시 clear 와 함께 잔류 custom reason 차단).
          'detail': _detail.text.trim().isEmpty ? null : _detail.text.trim(),
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
    final bool isOther = _reasonCode == 'OTHER';
    // ★기타 선택 시 직접 사유 필수 — trim 후 빈칸이면 제출 불가(placeholder도 '필수'로 전환).
    final bool detailMissing = isOther && _detail.text.trim().isEmpty;
    return PopScope(
      canPop: !_submitting, // 제출 중 시스템 뒤로가기 차단(배경탭·드래그는 showModalBottomSheet 에서 항상 차단)
      child: SafeArea(
        child: SingleChildScrollView(
        controller: _scroll,
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
            Row(
              children: [
                const Expanded(
                  child: Text('신고하기',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ),
                // 배경탭·드래그 닫기를 막았으므로 명시적 닫기 버튼 제공. 제출 중엔 비활성(닫기 차단), 제출 전엔 취소(false).
                IconButton(
                  onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted, size: 22),
                  splashRadius: 20,
                  tooltip: '닫기',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              // ★Toss restyle: 골드 경고 = borderless tonal(α.12) r12 — 외곽선 제거.
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
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
                  onTap: () => setState(() {
                    if (_reasonCode != r['code']) _detail.clear(); // 사유 변경 시 이전 입력(특히 OTHER 직접사유) 잔류·오전송 방지
                    _reasonCode = r['code'];
                  }),
                  behavior: HitTestBehavior.opaque,
                  // ★Toss restyle: 선택형 행 = 선택 blueDeep / 비선택 surfaceElevated, 외곽선 없음(전역 칩 문법).
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.blueDeep : AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r['label']!,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(r['desc']!,
                                style: TextStyle(
                                    color: selected
                                        ? AppColors.textSecondary
                                        : AppColors.textMuted,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: selected ? AppColors.textPrimary : AppColors.textMuted,
                        size: 20,
                      ),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              key: const Key('report_detail_field'),
              controller: _detail,
              focusNode: _detailFocus,
              onChanged: (_) => setState(() {}), // 기타 사유 입력 시 제출 버튼 활성/비활성 실시간 반영
              maxLines: 3,
              maxLength: 500,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: isOther ? '신고 사유를 입력해 주세요 (필수)' : '상세 내용을 입력해 주세요 (선택)',
                hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                // ★Toss restyle: 입력 필드 = filled surfaceElevated · borderless r12(전역 필드 문법).
                filled: true,
                fillColor: AppColors.surfaceElevated,
                counterStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: (_reasonCode == null || _submitting || detailMissing) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
                  disabledBackgroundColor: AppColors.surfaceElevated,
                  disabledForegroundColor: AppColors.textMuted,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
      ),
    );
  }
}
