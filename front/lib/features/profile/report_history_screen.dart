import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';

/// 내 신고 진행 상황 — GET /api/reports/me (백엔드 Report status 그대로 노출).
/// 신규 기능 아님: 백엔드(상태/메모/처리)는 이미 존재, 사용자 조회 화면만 추가.
class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  static const _reasonLabels = {
    'FRAUD': '사기 의심',
    'FAKE': '가품 / 위조',
    'ABUSIVE_PRICE': '시세 교란',
    'INSULT': '욕설 / 비방',
    'SPAM': '스팸 / 광고',
    'OTHER': '기타',
  };

  static const _targetLabels = {
    'TRADE': '거래글',
    'USER': '사용자',
    'CHAT': '채팅',
    'BUY_ORDER': '구매 요청',
  };

  // 백엔드 status (PENDING/REVIEWED/RESOLVED/DISMISSED) → 사용자 라벨 + 색.
  static const _statusLabels = {
    'PENDING': '접수됨',
    'REVIEWED': '검토 중',
    'RESOLVED': '처리 완료',
    'DISMISSED': '반려',
  };

  Color _statusColor(String s) {
    switch (s) {
      case 'RESOLVED':
        return AppColors.green;
      case 'REVIEWED':
        return AppColors.blue;
      case 'DISMISSED':
        return AppColors.textMuted;
      case 'PENDING':
      default:
        return AppColors.gold;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.get('/api/reports/me');
      if (!mounted) return;
      final list = (res['data'] as List?) ?? const [];
      setState(() {
        _items = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppErrorToast.show(context, '신고 내역을 불러올 수 없습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        title: const Text('신고 진행 상황'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    '신고 내역이 없습니다',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.blue,
                  onRefresh: _load,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(), // #9: 항목 적어도 pull-refresh
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _buildItem(_items[index]),
                  ),
                ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final reason = item['reason']?.toString() ?? '';
    final targetType = item['targetType']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'PENDING';
    final detail = item['detail']?.toString() ?? '';
    final createdAt = item['createdAt']?.toString() ?? '';
    final adminMemo = item['adminMemo']?.toString() ?? '';

    final reasonLabel = _reasonLabels[reason] ?? reason;
    final targetLabel = _targetLabels[targetType] ?? targetType;
    final statusLabel = _statusLabels[status] ?? status;
    final statusColor = _statusColor(status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [if (targetLabel.isNotEmpty) targetLabel, reasonLabel].join(' · '),
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // 처리 완료/반려 시 관리자 메모가 있으면 사용자에게 결과 안내.
          if (adminMemo.isNotEmpty &&
              (status == 'RESOLVED' || status == 'DISMISSED')) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.support_agent_rounded,
                      color: AppColors.textMuted, size: 15),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      adminMemo,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (createdAt.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              createdAt.split('.').first.replaceFirst('T', ' '),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
