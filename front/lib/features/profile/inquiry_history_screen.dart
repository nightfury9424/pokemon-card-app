import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';

/// 내 문의 내역 — GET /api/inquiries/me. 관리자 답변(adminReply) 상태 노출.
class InquiryHistoryScreen extends StatefulWidget {
  const InquiryHistoryScreen({super.key});

  @override
  State<InquiryHistoryScreen> createState() => _InquiryHistoryScreenState();
}

class _InquiryHistoryScreenState extends State<InquiryHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  static const _categoryLabels = {
    'cardAddRequest': '카드 추가 요청',
    'price': '시세/가격',
    'trade': '거래/채팅',
    'account': '계정/닉네임',
    'bug': '버그',
    'feature': '기능 제안',
    'etc': '기타',
  };

  static const _statusLabels = {
    'OPEN': '접수됨',
    'ANSWERED': '답변 완료',
    'CLOSED': '종료',
  };

  Color _statusColor(String s) {
    switch (s) {
      case 'ANSWERED':
        return AppColors.green;
      case 'CLOSED':
        return AppColors.textMuted;
      case 'OPEN':
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
      final res = await ApiClient.get('/api/inquiries/me');
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
      AppErrorToast.show(context, '문의 내역을 불러올 수 없습니다');
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
        title: const Text('내 문의 내역'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    '문의 내역이 없습니다',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.blue,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _buildItem(_items[index]),
                  ),
                ),
    );
  }

  Widget _buildItem(Map<String, dynamic> item) {
    final category = item['category']?.toString() ?? '';
    final title = item['title']?.toString() ?? '';
    final status = item['status']?.toString() ?? 'OPEN';
    final content = item['content']?.toString() ?? '';
    final adminReply = item['adminReply']?.toString() ?? '';
    final createdAt = item['createdAt']?.toString() ?? '';

    final catLabel = _categoryLabels[category] ?? category;
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
                  title.isEmpty ? catLabel : title,
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
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              content,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          // 관리자 답변
          if (adminReply.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.support_agent_rounded,
                          color: AppColors.green, size: 15),
                      SizedBox(width: 6),
                      Text('관리자 답변',
                          style: TextStyle(
                              color: AppColors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    adminReply,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.4,
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
