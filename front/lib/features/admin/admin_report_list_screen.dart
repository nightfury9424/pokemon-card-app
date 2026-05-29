import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import 'admin_api.dart';

/// 2026-05-29 admin Stage 0 — 신고 list view + 처리 sheet.
///
/// 정책:
///   - default filter: status=PENDING (운영 우선순위)
///   - status 필터 chip: 전체 / PENDING / REVIEWED / RESOLVED / DISMISSED
///   - row 클릭 → 처리 sheet (status 변경 + admin memo + resolution action)
///   - 위험 액션 (resolution_action 선택) 시 confirm dialog
///   - 성공/실패 토스트 명확
class AdminReportListScreen extends StatefulWidget {
  const AdminReportListScreen({super.key});

  @override
  State<AdminReportListScreen> createState() => _AdminReportListScreenState();
}

class _AdminReportListScreenState extends State<AdminReportListScreen> {
  String _statusFilter = 'PENDING';
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await AdminApi.listReports(
        status: _statusFilter == 'ALL' ? null : _statusFilter,
        size: 50,
      );
      final content = (data['content'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _rows = content
            .whereType<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
        _pendingCount = (data['pendingCount'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppErrorToast.show(context, '신고 목록을 불러오지 못했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('신고 처리 ($_pendingCount건 대기)',
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildFilterRow(),
            const Divider(height: 1, color: AppColors.dividerSoft),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.blue, strokeWidth: 2))
                  : _rows.isEmpty
                      ? const Center(
                          child: Text('신고 없음',
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 13)))
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const Divider(
                              height: 1,
                              color: AppColors.dividerSoft,
                              indent: 16),
                          itemBuilder: (_, i) => _buildRow(_rows[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final filters = ['ALL', 'PENDING', 'REVIEWED', 'RESOLVED', 'DISMISSED'];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final sel = _statusFilter == f;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () {
                  setState(() => _statusFilter = f);
                  _load();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.blue : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? AppColors.blue : AppColors.divider),
                  ),
                  child: Text(
                    f == 'ALL' ? '전체' : f,
                    style: TextStyle(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> r) {
    final status = r['status'] as String? ?? 'PENDING';
    final targetType = r['targetType'] as String? ?? '';
    final reason = r['reason'] as String? ?? '';
    final reporterNick = r['reporterNickname'] as String? ?? r['reporterId'] ?? '';
    final targetSummary = r['targetSummary'] as String? ?? r['targetId'] ?? '';
    final detail = r['detail'] as String? ?? '';

    final statusColor = switch (status) {
      'PENDING' => AppColors.gold,
      'REVIEWED' => AppColors.blueLight,
      'RESOLVED' => AppColors.green,
      'DISMISSED' => AppColors.textMuted,
      _ => AppColors.textMuted,
    };

    return InkWell(
      onTap: () => _showHandleSheet(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.4), width: 0.5),
                  ),
                  child: Text(status,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 6),
                Text('[$targetType]',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(reason,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('신고자: $reporterNick  /  대상: $targetSummary',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11.5)),
            if (detail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      height: 1.4)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showHandleSheet(Map<String, dynamic> r) async {
    final reportId = r['reportId'] as String;
    final memoCtrl = TextEditingController(text: r['adminMemo'] as String? ?? '');
    String? selectedStatus;
    String? selectedAction;

    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('신고 처리',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
                  _SheetSection(
                    title: 'status 변경',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['REVIEWED', 'RESOLVED', 'DISMISSED']
                          .map((s) {
                        final sel = selectedStatus == s;
                        return ChoiceChip(
                          label: Text(s),
                          selected: sel,
                          onSelected: (v) =>
                              setSheet(() => selectedStatus = v ? s : null),
                          selectedColor: AppColors.blue,
                          backgroundColor: AppColors.surface,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide(
                              color: sel ? AppColors.blue : AppColors.divider),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                  ),
                  _SheetSection(
                    title: 'resolution action (선택)',
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['NONE', 'SUSPEND_USER', 'DELETE_TRADE', 'DISMISS']
                          .map((a) {
                        final sel = selectedAction == a;
                        return ChoiceChip(
                          label: Text(a),
                          selected: sel,
                          onSelected: (v) =>
                              setSheet(() => selectedAction = v ? a : null),
                          selectedColor: AppColors.blueLight,
                          backgroundColor: AppColors.surface,
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          side: BorderSide(
                              color: sel
                                  ? AppColors.blueLight
                                  : AppColors.divider),
                          showCheckmark: false,
                        );
                      }).toList(),
                    ),
                  ),
                  _SheetSection(
                    title: 'admin memo (선택)',
                    child: TextField(
                      controller: memoCtrl,
                      maxLines: 3,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '처리 메모 / 근거',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted, fontSize: 12.5),
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.blue, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: selectedStatus == null
                            ? null
                            : () => Navigator.pop(ctx, {
                                  'status': selectedStatus,
                                  'memo': memoCtrl.text.trim(),
                                  'action': selectedAction,
                                }),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          disabledBackgroundColor: AppColors.divider,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('처리하기',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    memoCtrl.dispose();
    if (result == null || !mounted) return;

    // 위험 액션 (SUSPEND_USER / DELETE_TRADE) confirm.
    final action = result['action'];
    if (action == 'SUSPEND_USER' || action == 'DELETE_TRADE') {
      final confirmed = await AppConfirmDialog.show(
        context,
        title: '$action 처리할까요?',
        message: '대상에게 즉시 적용되며 audit log에 기록됩니다.',
        confirmLabel: '$action 처리',
        destructive: true,
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      await AdminApi.updateReportStatus(
        reportId,
        status: result['status']!,
        adminMemo: result['memo']?.isEmpty == true ? null : result['memo'],
        resolutionAction:
            (action == null || action == 'NONE') ? 'NONE' : action,
      );
      if (!mounted) return;
      AppSuccessToast.show(context, '신고 처리 완료');
      _load();
    } catch (_) {
      if (!mounted) return;
      AppErrorToast.show(context, '신고 처리에 실패했어요');
    }
  }
}

class _SheetSection extends StatelessWidget {
  final String title;
  final Widget child;
  const _SheetSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          child,
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
