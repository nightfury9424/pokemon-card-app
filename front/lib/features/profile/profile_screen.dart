import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_confirm_dialog.dart';
import '../../core/widgets/user_avatar.dart';
import '../auth/auth_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  String? _userId;
  bool _loading = true;

  // 내 자산 통계
  int _totalCards = 0;
  int _activeTrades = 0;
  int _activeBuyOrders = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final meRes = await ApiClient.get('/api/users/me');
      final user = meRes['data'] as Map<String, dynamic>?;
      final userId = user?['userId'] as String?;

      int totalCards = 0;
      int activeTrades = 0;
      int activeBuyOrders = 0;

      if (userId != null) {
        final results = await Future.wait([
          ApiClient.get('/api/assets', params: {'userId': userId}).catchError((_) => {'data': []}),
          ApiClient.get('/api/trades', params: {'sellerId': userId, 'status': 'OPEN', 'page': 0, 'size': 1}).catchError((_) => {'data': {}}),
          ApiClient.get('/api/buy-orders/me').catchError((_) => {'data': []}),
        ]);

        final assets = results[0]['data'];
        if (assets is List) {
          totalCards = assets.fold<int>(0, (s, a) => s + ((a['quantity'] as num?)?.toInt() ?? 1));
        }

        final tradesData = results[1]['data'];
        if (tradesData is Map) {
          activeTrades = (tradesData['totalElements'] as num?)?.toInt() ?? 0;
        }

        final buyOrders = results[2]['data'];
        if (buyOrders is List) {
          activeBuyOrders = buyOrders
              .where((o) => (o is Map) && o['status'] == 'OPEN')
              .length;
        }
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _userId = userId;
        _totalCards = totalCards;
        _activeTrades = activeTrades;
        _activeBuyOrders = activeBuyOrders;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await AppConfirmDialog.show(
      context,
      title: '로그아웃',
      message: '로그아웃 하시겠습니까?',
      confirmLabel: '로그아웃',
      destructive: true,
    );
    if (confirm == true && mounted) {
      await AuthService.logout();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue, strokeWidth: 2))
          : CustomScrollView(
              slivers: [
                _buildAppBar(),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileHeader(),
                        const SizedBox(height: 16),
                        _buildStatRow(),
                        const SizedBox(height: 28),
                        _buildSectionLabel('계정'),
                        const SizedBox(height: 8),
                        _buildMenuGroup([
                          _MenuItem(
                            icon: Icons.edit_rounded,
                            iconColor: AppColors.blue,
                            label: '닉네임 변경',
                            onTap: () => context.push('/profile/edit-nickname'),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _buildSectionLabel('내 활동'),
                        const SizedBox(height: 8),
                        _buildMenuGroup([
                          _MenuItem(
                            icon: Icons.style_rounded,
                            iconColor: AppColors.blue,
                            label: '내 자산',
                            sub: '$_totalCards장 보유',
                            onTap: () => context.push('/assets'),
                          ),
                          _MenuItem(
                            icon: Icons.shopping_cart_rounded,
                            iconColor: const Color(0xFFF59E0B),
                            label: '내 매수 주문',
                            sub: _activeBuyOrders > 0
                                ? 'OPEN $_activeBuyOrders건'
                                : '매수 호가 없음',
                            onTap: () =>
                                context.push('/assets?tab=buy'),
                          ),
                          _MenuItem(
                            icon: Icons.receipt_long_rounded,
                            iconColor: const Color(0xFF10B981),
                            label: '내 판매 내역',
                            sub: _activeTrades > 0 ? '진행 중 $_activeTrades건' : null,
                            onTap: () => context.push('/my-trades', extra: {'sellerId': _userId}),
                          ),
                          _MenuItem(
                            icon: Icons.favorite_rounded,
                            iconColor: AppColors.red,
                            label: '관심 목록',
                            onTap: () => context.push('/favorites'),
                          ),
                          _MenuItem(
                            icon: Icons.qr_code_scanner_rounded,
                            iconColor: const Color(0xFF8B5CF6),
                            label: '카드 스캔',
                            onTap: () => context.push('/scanner'),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _buildSectionLabel('고객 지원'),
                        const SizedBox(height: 8),
                        _buildMenuGroup([
                          _MenuItem(
                            icon: Icons.flag_rounded,
                            iconColor: const Color(0xFFF59E0B),
                            label: '신고 진행 상황',
                            onTap: () => _showComingSoon('신고 진행 상황'),
                          ),
                          _MenuItem(
                            icon: Icons.chat_bubble_outline_rounded,
                            iconColor: AppColors.blueLight,
                            label: '문의하기',
                            onTap: () => _showComingSoon('문의하기'),
                          ),
                          _MenuItem(
                            icon: Icons.info_outline_rounded,
                            iconColor: AppColors.textMuted,
                            label: '앱 정보',
                            sub: 'v1.0.0',
                            onTap: () {},
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _buildMenuGroup([
                          _MenuItem(
                            icon: Icons.logout_rounded,
                            iconColor: AppColors.red,
                            label: '로그아웃',
                            labelColor: AppColors.red,
                            onTap: _logout,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.bg,
      floating: true,
      elevation: 0,
      title: const Text('MY'),
    );
  }

  Widget _buildProfileHeader() {
    final nickname = _user?['nickname'] as String? ?? '-';
    final email = _user?['email'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          UserAvatar(imageUrl: _user?['profileImageUrl'] as String?),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nickname,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    email,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow() {
    return Row(
      children: [
        _StatChip(label: '보유 카드', value: '$_totalCards장'),
        const SizedBox(width: 10),
        _StatChip(label: '판매 중', value: '$_activeTrades건'),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildMenuGroup(List<_MenuItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final isLast = i == items.length - 1;
          return _MenuRow(item: item, isLast: isLast);
        }),
      ),
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature 기능은 준비 중입니다.'),
        backgroundColor: AppColors.surfaceCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color? labelColor;
  final String? sub;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.labelColor,
    this.sub,
    required this.onTap,
  });
}

class _MenuRow extends StatelessWidget {
  final _MenuItem item;
  final bool isLast;

  const _MenuRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: item.onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: item.iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        style: TextStyle(
                          color: item.labelColor ?? AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (item.sub != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.sub!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textMuted,
                  size: 18,
                ),
              ],
            ),
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 66),
              child: Container(height: 0.5, color: AppColors.divider),
            ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
