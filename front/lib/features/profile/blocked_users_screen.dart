import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_list_ui.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/widgets/empty_state.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  final Set<String> _unblocking = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiClient.getBlockedUsers();
      if (!mounted) return;
      setState(() {
        _items = list
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppErrorToast.show(context, '차단 목록을 불러올 수 없습니다');
    }
  }

  Future<void> _unblock(String userId) async {
    if (_unblocking.contains(userId)) return;
    setState(() => _unblocking.add(userId));
    try {
      final res = await ApiClient.unblockUser(userId);
      if (!mounted) return;
      if (res['status'] != 'success') {
        AppErrorToast.show(context, '차단 해제에 실패했습니다');
        return;
      }
      setState(() => _items.removeWhere((item) => item['blockedId'] == userId));
      AppSuccessToast.show(context, '차단을 해제했습니다');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '차단 해제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _unblocking.remove(userId));
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
        title: const Text('차단한 사용자'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          // 로드 실패 시 에러 토스트 후 _items가 빈 채로 남음(에러 상태 미분리) — 분기 유지, 표현만 교체.
          : _items.isEmpty
              ? const EmptyState(
                  icon: Icons.person_off_rounded,
                  title: '차단한 사용자가 없어요',
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AppGroupCard(
                      dividerIndent: 68,
                      children: [
                        for (final item in _items) _buildRow(item),
                      ],
                    ),
                  ],
                ),
    );
  }

  Widget _buildRow(Map<String, dynamic> item) {
    final blockedId = item['blockedId']?.toString() ?? '';
    final blockedAt = item['blockedAt']?.toString() ?? '';
    // Phase 1 hotfix: nickname 우선. 없으면 "알 수 없는 사용자". raw user_id 노출 X.
    final nickname = item['blockedNickname']?.toString();
    final displayName =
        (nickname != null && nickname.isNotEmpty) ? nickname : '알 수 없는 사용자';
    final busy = _unblocking.contains(blockedId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.surfaceElevated,
            child: Icon(
              Icons.person_off_rounded,
              color: AppColors.textMuted,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (blockedAt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    blockedAt.split('.').first.replaceFirst('T', ' '),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed:
                busy || blockedId.isEmpty ? null : () => _unblock(blockedId),
            child: Text(busy ? '처리 중' : '차단 해제'),
          ),
        ],
      ),
    );
  }
}
