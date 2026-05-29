import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import 'admin_api.dart';

/// 2026-05-29 admin Stage 0 — 거래글 admin 삭제.
///
/// 정책:
///   - tradeId 직접 입력 후 삭제 (검색 UI는 v1.1). Stage 0 MVP.
///   - 사유 입력 필수 (audit log)
///   - confirm dialog 필수 (destructive)
///   - idempotency: 이미 DELETED 상태도 backend 가 silent success (admin_actions audit 만 기록).
class AdminTradePostManageScreen extends StatefulWidget {
  const AdminTradePostManageScreen({super.key});

  @override
  State<AdminTradePostManageScreen> createState() =>
      _AdminTradePostManageScreenState();
}

class _AdminTradePostManageScreenState
    extends State<AdminTradePostManageScreen> {
  final _tradeIdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _tradeIdCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final tradeId = _tradeIdCtrl.text.trim();
    final reason = _reasonCtrl.text.trim();
    if (tradeId.isEmpty) {
      AppErrorToast.show(context, '거래글 ID를 입력해주세요');
      return;
    }
    if (reason.isEmpty) {
      AppErrorToast.show(context, '삭제 사유를 입력해주세요 (audit log)');
      return;
    }

    final confirmed = await AppConfirmDialog.show(
      context,
      title: '거래글 $tradeId 삭제할까요?',
      message: 'soft delete 됩니다. 양쪽 채팅방에 SYSTEM 메시지 fan-out + audit log 기록.',
      confirmLabel: '거래글 삭제',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await AdminApi.deleteTradePost(tradeId, reason);
      if (!mounted) return;
      AppSuccessToast.show(context, '거래글 삭제 완료');
      _tradeIdCtrl.clear();
      _reasonCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('TRADE_NOT_FOUND')) {
        AppErrorToast.show(context, '해당 거래글을 찾을 수 없어요');
      } else {
        AppErrorToast.show(context, '삭제 처리에 실패했어요');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('거래글 admin 삭제',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF332B1A),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFFDE68A), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '거래글 soft delete + 양쪽 채팅방 SYSTEM 알림 + admin_actions 기록.',
                      style: TextStyle(
                          color: Color(0xFFFDE68A),
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _label('거래글 ID *'),
            _textField(_tradeIdCtrl, '예: trade-uuid-123'),
            const SizedBox(height: 16),
            _label('삭제 사유 * (audit log)'),
            _textField(_reasonCtrl, '예: 사기 신고 다수, 부적절 콘텐츠', maxLines: 3),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _delete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.red,
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
                    : const Text('거래글 삭제 처리',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800)),
    );
  }

  Widget _textField(TextEditingController ctrl, String hint,
      {int maxLines = 1}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        filled: true,
        fillColor: AppColors.surfaceCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
        ),
      ),
    );
  }
}
