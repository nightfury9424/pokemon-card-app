import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';

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
      await ApiClient.unblockUser(userId);
      if (!mounted) return;
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
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    '차단한 사용자가 없습니다',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final blockedId = item['blockedId']?.toString() ?? '';
                    final blockedAt = item['blockedAt']?.toString() ?? '';
                    final busy = _unblocking.contains(blockedId);
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
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
                                  blockedId,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (blockedAt.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    blockedAt.split('.').first.replaceFirst('T', ' '),
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: busy || blockedId.isEmpty
                                ? null
                                : () => _unblock(blockedId),
                            child: Text(busy ? '처리 중' : '차단 해제'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
