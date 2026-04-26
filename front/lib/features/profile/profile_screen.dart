import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  String? _userId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      if (!mounted) return;
      setState(() {
        _user = res['data'] as Map<String, dynamic>?;
        _userId = _user?['userId'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: const Text('로그아웃', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('로그아웃 하시겠습니까?', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('취소', style: TextStyle(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('로그아웃', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await TokenStorage.delete();
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nickname = _user?['nickname'] as String? ?? '-';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('내 정보', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.blue))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 프로필 카드
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A3A6A), Color(0xFF0D2040)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: AppColors.blue.withOpacity(0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.blue.withOpacity(0.5), width: 2),
                        ),
                        child: const Icon(Icons.person, color: AppColors.blue, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(nickname,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          const Text('포켓몬 카드 컬렉터', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 메뉴 섹션
                _buildSection('내 활동', [
                  _buildMenuItem(Icons.style_rounded, '내 자산', () => context.push('/assets')),
                  _buildMenuItem(Icons.favorite_rounded, '관심 목록', () => context.push('/favorites'),
                      iconColor: AppColors.red),
                  _buildMenuItem(Icons.qr_code_scanner, '카드 스캔', () => context.push('/scanner')),
                ]),
                const SizedBox(height: 16),
                _buildSection('앱 설정', [
                  _buildMenuItem(Icons.info_outline_rounded, '앱 정보', () {}),
                  _buildMenuItem(Icons.logout_rounded, '로그아웃', _logout, color: AppColors.red),
                ]),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(children: items),
        ),
      ],
    );
  }

  Widget _buildMenuItem(IconData icon, String label, VoidCallback onTap,
      {Color? color, Color? iconColor}) {
    final textColor = color ?? AppColors.textPrimary;
    final icColor = iconColor ?? color ?? AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: icColor, size: 20),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: TextStyle(color: textColor, fontSize: 15))),
            Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}
