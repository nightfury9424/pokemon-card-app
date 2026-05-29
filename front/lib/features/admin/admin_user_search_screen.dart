import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import 'admin_api.dart';

/// 2026-05-29 admin Stage 0 — 사용자 검색 + 정지/복구.
///
/// 정책:
///   - 닉네임 partial / 이메일 prefix 검색 (백엔드 정책)
///   - row 우측 정지/복구 액션 (현재 상태 따라 분기)
///   - 정지/복구 confirm 필수 (위험 액션)
///   - admin allowlist 사용자 정지 시도 → 백엔드 403 ADMIN_USER_NOT_SUSPENDABLE 반환
///   - 탈퇴 사용자 정지 시도 → 백엔드 409 USER_ALREADY_DELETED 반환
class AdminUserSearchScreen extends StatefulWidget {
  const AdminUserSearchScreen({super.key});

  @override
  State<AdminUserSearchScreen> createState() => _AdminUserSearchScreenState();
}

class _AdminUserSearchScreenState extends State<AdminUserSearchScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    try {
      final list = await AdminApi.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppErrorToast.show(context, '검색에 실패했어요');
    }
  }

  Future<void> _suspendFlow(Map<String, dynamic> user) async {
    final nick = user['nickname'] as String? ?? '';
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('$nick 사용자 정지',
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('정지 사유를 입력해주세요 (audit log에 기록됨).',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonCtrl,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: '정지 사유',
                hintStyle: const TextStyle(
                    color: AppColors.textMuted, fontSize: 12.5),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('정지 처리',
                style: TextStyle(
                    color: AppColors.red, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (confirmed != true || !mounted) return;
    if (reason.isEmpty) {
      AppErrorToast.show(context, '정지 사유는 필수에요');
      return;
    }
    try {
      await AdminApi.suspendUser(user['userId'] as String, reason);
      if (!mounted) return;
      AppSuccessToast.show(context, '$nick 정지 처리됨');
      _search();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (msg.contains('ADMIN_USER_NOT_SUSPENDABLE')) {
        AppErrorToast.show(context, '관리자 계정은 정지할 수 없어요');
      } else if (msg.contains('USER_ALREADY_DELETED')) {
        AppErrorToast.show(context, '이미 탈퇴한 사용자에요');
      } else {
        AppErrorToast.show(context, '정지 처리에 실패했어요');
      }
    }
  }

  Future<void> _unsuspendFlow(Map<String, dynamic> user) async {
    final nick = user['nickname'] as String? ?? '';
    final confirmed = await AppConfirmDialog.show(
      context,
      title: '$nick 정지 해제할까요?',
      message: '정지 해제 즉시 모든 API 호출이 다시 가능해집니다.',
      confirmLabel: '정지 해제',
    );
    if (confirmed != true || !mounted) return;
    try {
      await AdminApi.unsuspendUser(user['userId'] as String);
      if (!mounted) return;
      AppSuccessToast.show(context, '$nick 정지 해제됨');
      _search();
    } catch (_) {
      if (!mounted) return;
      AppErrorToast.show(context, '정지 해제에 실패했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: const Text('사용자 검색 / 정지',
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '닉네임 또는 이메일 prefix',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5),
                        filled: true,
                        fillColor: AppColors.surfaceElevated,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _search(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _loading ? null : _search,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.blue,
                      disabledBackgroundColor: AppColors.divider,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('검색'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.dividerSoft),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.blue, strokeWidth: 2))
                  : _results.isEmpty
                      ? const Center(
                          child: Text('검색 결과 없음',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _results.length,
                          separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppColors.dividerSoft,
                              indent: 16),
                          itemBuilder: (_, i) => _buildRow(_results[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> user) {
    final nick = user['nickname'] as String? ?? '(닉네임 없음)';
    final email = user['email'] as String?;
    final suspended = user['suspended'] == true;
    final deleted = user['deleted'] == true;
    final reason = user['suspensionReason'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(nick,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    if (deleted)
                      _statusChip('탈퇴', AppColors.textMuted)
                    else if (suspended)
                      _statusChip('정지', AppColors.red)
                    else
                      _statusChip('정상', AppColors.green),
                  ],
                ),
                const SizedBox(height: 2),
                Text(email ?? '(이메일 비공개)',
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 11.5)),
                if (suspended && reason != null) ...[
                  const SizedBox(height: 4),
                  Text('정지 사유: $reason',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (!deleted) ...[
            const SizedBox(width: 8),
            if (suspended)
              TextButton(
                onPressed: () => _unsuspendFlow(user),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.green),
                child: const Text('정지 해제',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              )
            else
              TextButton(
                onPressed: () => _suspendFlow(user),
                style: TextButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('정지',
                    style: TextStyle(fontWeight: FontWeight.w800)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}
