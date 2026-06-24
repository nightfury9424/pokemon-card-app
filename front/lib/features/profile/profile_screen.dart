import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/app_info_toast.dart';
import '../board/board_screen.dart';

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
                    // 하단 여백 = 셸 스캔 FAB 돌출 클리어런스(공통 디자인 상수, MainShell과 공유).
                    padding: const EdgeInsets.fromLTRB(
                        16, 0, 16, AppDimens.bottomContentInsetForScanFab),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileHeader(),
                        const SizedBox(height: 16),
                        _buildStatRow(),
                        const SizedBox(height: 28),
                        _buildSectionLabel('내 거래'),
                        const SizedBox(height: 10),
                        _buildTradeGrid(),
                        const SizedBox(height: 24),
                        _buildSectionLabel('서비스'),
                        const SizedBox(height: 10),
                        _buildServiceGrid(),
                        const SizedBox(height: 24),
                        _buildSectionLabel('고객 지원'),
                        const SizedBox(height: 10),
                        _buildSupportGrid(),
                        const SizedBox(height: 28),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            "본 앱은 비공식 팬 서비스로, The Pokémon Company / Nintendo / Creatures Inc. / GAME FREAK inc.와 제휴·후원 관계가 없습니다. 'Pokémon', '포켓몬' 및 관련 명칭·캐릭터·이미지의 저작권 및 상표권은 각 권리자에게 있습니다.",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 24),
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
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
          tooltip: '설정',
          onPressed: () => context.push('/settings'),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildProfileHeader() {
    final nickname = _user?['nickname'] as String? ?? '-';

    // #3: 카드 탭 → 프로필 편집(닉네임). 별도 '닉네임 변경' 메뉴 통합. (프로필 사진 변경=post-launch)
    return InkWell(
      onTap: () async {
        await context.push('/profile/edit-nickname');
        if (mounted) _loadData();
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
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
                  const SizedBox(height: 3),
                  const Text('프로필 편집',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow() {
    return Row(
      children: [
        _StatChip(
            label: '보유 카드',
            value: '$_totalCards종',
            onTap: () => context.push('/assets')),
        const SizedBox(width: 10),
        _StatChip(
            label: '판매중',
            value: '$_activeTrades건',
            onTap: () => context.push('/assets?tab=selling')),
        const SizedBox(width: 10),
        _StatChip(
            label: '구매중',
            value: '$_activeBuyOrders건',
            onTap: () => context.push('/assets?tab=buy')),
      ],
    );
  }

  // 한 행을 등간격 Expanded 타일로. IntrinsicHeight+stretch → 같은 행 타일은 항상 동일 높이
  // (준비중 핀이 붙어 높이가 달라져도 행 내 정렬 안 깨짐).
  Widget _gridRow(List<Widget> tiles) {
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 12));
      children.add(Expanded(child: tiles[i]));
    }
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  // 내 거래 = 2x2 그리드. 핵심 숫자는 stat row에 두고, 타일엔 '바로 처리할' 액션 배지만(매수 OPEN/판매 진행중).
  Widget _buildTradeGrid() {
    return Column(
      children: [
        _gridRow([
          _HubTile(
            icon: Icons.style_rounded,
            iconColor: AppColors.blue,
            label: '내 카드',
            onTap: () => context.push('/assets'),
          ),
          _HubTile(
            icon: Icons.shopping_cart_rounded,
            iconColor: const Color(0xFFF59E0B),
            label: '매수',
            badgeCount: _activeBuyOrders,
            onTap: () => context.push('/assets?tab=buy'),
          ),
        ]),
        const SizedBox(height: 12),
        _gridRow([
          _HubTile(
            icon: Icons.receipt_long_rounded,
            iconColor: const Color(0xFF10B981),
            label: '판매',
            badgeCount: _activeTrades,
            // _userId null이면 sellerId 누락 → trade_list가 메인 거래 화면으로 잘못 진입.
            onTap: _userId == null
                ? null
                : () => context.push('/my-trades', extra: {'sellerId': _userId}),
          ),
          _HubTile(
            icon: Icons.favorite_rounded,
            iconColor: AppColors.red,
            label: '관심',
            onTap: () => context.push('/favorites'),
          ),
        ]),
      ],
    );
  }

  // 서비스 = 3-col 그리드. 게시판(활성) + 오리파/경매(준비중 회색).
  Widget _buildServiceGrid() {
    return _gridRow([
      _HubTile(
        icon: Icons.forum_rounded,
        iconColor: AppColors.blueLight,
        label: '게시판',
        // 게시판은 아직 go_router route 아님 — 공지배너와 동일하게 Navigator.push.
        onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => const BoardScreen())),
      ),
      _HubTile(
        icon: Icons.question_mark_rounded,
        iconColor: AppColors.textMuted,
        label: '?',
        comingSoon: true,
        onTap: () => AppInfoToast.show(context, '오픈 준비 중이에요'),
      ),
      _HubTile(
        icon: Icons.question_mark_rounded,
        iconColor: AppColors.textMuted,
        label: '?',
        comingSoon: true,
        onTap: () => AppInfoToast.show(context, '오픈 준비 중이에요'),
      ),
    ]);
  }

  // 고객 지원 = 3-col 그리드 (서비스와 톤 일치).
  Widget _buildSupportGrid() {
    return _gridRow([
      _HubTile(
        icon: Icons.chat_bubble_outline_rounded,
        iconColor: AppColors.blueLight,
        label: '문의하기',
        onTap: () => context.push('/support'),
      ),
      _HubTile(
        icon: Icons.inbox_outlined,
        iconColor: AppColors.blueLight,
        label: '내 문의',
        onTap: () => context.push('/profile/inquiries'),
      ),
      _HubTile(
        icon: Icons.flag_rounded,
        iconColor: const Color(0xFFF59E0B),
        label: '신고내역',
        onTap: () => context.push('/profile/reports'),
      ),
    ]);
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

}

/// 허브 그리드 타일 — 아이콘 칩 + 라벨. 준비중이면 회색 + '준비중' 핀, 액션 배지(매수/판매)는 우상단.
class _HubTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int? badgeCount;
  final bool comingSoon;
  final VoidCallback? onTap;

  const _HubTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.badgeCount,
    this.comingSoon = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = !comingSoon && (badgeCount ?? 0) > 0;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        // stretch 된 높이 안에서 아이콘+라벨(+핀)을 세로 중앙 정렬.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: comingSoon ? 0.08 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 22),
                  ),
                  if (showBadge)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: AppColors.blue,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.surfaceCard, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          badgeCount! > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: comingSoon ? AppColors.textMuted : AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (comingSoon) ...[
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('준비중',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap; // B2-9: 탭하면 내자산 해당 탭으로.

  const _StatChip({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Container(
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
    );
    return Expanded(
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: content,
            ),
    );
  }
}
