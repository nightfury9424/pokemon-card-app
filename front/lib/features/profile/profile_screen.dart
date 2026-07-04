import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_dimens.dart';
import '../../core/widgets/user_avatar.dart';
import '../../core/widgets/app_list_ui.dart';
import '../board/board_screen.dart';
import 'my_activity_screen.dart';

/// MY — ★Toss restyle(2026-07-04): 빈 타일 그리드 → 리스트 그룹.
///  - 프로필: 박스 제거, 플레인 행 (큰 이름 + 편집 캡션 + chevron)
///  - 스탯: 3분할 박스 → 요약 카드 1장 (숫자 위계 + 세로 디바이더)
///  - 메뉴: 섹션별 그룹 카드 안의 행(아이콘·라벨·배지·chevron) — 밀도/스캔성 ↑
///  - 아이콘: 컬러 그라데이션 스쿼클(pseudo-3D) — 플랫 서피스 위 입체 포인트
///  - '준비 중 ?' 섹션 제거 (빈 약속 노출 안 함)
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
                        20, 4, 20, AppDimens.bottomContentInsetForScanFab),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProfileHeader(),
                        const SizedBox(height: 20),
                        _buildSummaryCard(),
                        const SizedBox(height: 28),
                        const AppSectionLabel('내 거래'),
                        const SizedBox(height: 8),
                        AppGroupCard(children: [
                          AppMenuRow(
                            icon: Icons.style_rounded,
                            color: AppColors.blue,
                            label: '내 카드',
                            onTap: () => context.push('/assets'),
                          ),
                          AppMenuRow(
                            icon: Icons.shopping_cart_rounded,
                            color: AppColors.gold,
                            label: '매수',
                            badgeCount: _activeBuyOrders,
                            onTap: () => context.push('/assets?tab=buy'),
                          ),
                          AppMenuRow(
                            icon: Icons.receipt_long_rounded,
                            color: AppColors.green,
                            label: '판매',
                            badgeCount: _activeTrades,
                            // _userId null이면 sellerId 누락 → trade_list가 메인 거래 화면으로 잘못 진입.
                            onTap: _userId == null
                                ? null
                                : () => context.push('/my-trades', extra: {'sellerId': _userId}),
                          ),
                          AppMenuRow(
                            icon: Icons.favorite_rounded,
                            color: AppColors.red,
                            label: '관심',
                            onTap: () => context.push('/favorites'),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        const AppSectionLabel('커뮤니티'),
                        const SizedBox(height: 8),
                        AppGroupCard(children: [
                          AppMenuRow(
                            icon: Icons.forum_rounded,
                            color: AppColors.blueLight,
                            label: '게시판',
                            // 게시판은 아직 go_router route 아님 — 공지배너와 동일하게 Navigator.push.
                            onTap: () => Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(builder: (_) => const BoardScreen())),
                          ),
                          AppMenuRow(
                            icon: Icons.history_rounded,
                            color: AppColors.blue,
                            label: '내 활동',
                            onTap: () => Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(builder: (_) => const MyActivityScreen())),
                          ),
                        ]),
                        const SizedBox(height: 24),
                        const AppSectionLabel('고객 지원'),
                        const SizedBox(height: 8),
                        AppGroupCard(children: [
                          AppMenuRow(
                            icon: Icons.chat_bubble_rounded,
                            color: AppColors.blueLight,
                            label: '문의하기',
                            onTap: () => context.push('/support'),
                          ),
                          AppMenuRow(
                            icon: Icons.inbox_rounded,
                            color: AppColors.blue,
                            label: '내 문의',
                            onTap: () => context.push('/profile/inquiries'),
                          ),
                          AppMenuRow(
                            icon: Icons.flag_rounded,
                            color: AppColors.gold,
                            label: '신고내역',
                            onTap: () => context.push('/profile/reports'),
                          ),
                        ]),
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

  /// 프로필 — 박스 없는 플레인 행. 이름이 화면의 주인공.
  Widget _buildProfileHeader() {
    final nickname = _user?['nickname'] as String? ?? '-';

    // #3: 탭 → 프로필 편집(닉네임). (프로필 사진 변경=post-launch)
    return InkWell(
      onTap: () async {
        await context.push('/profile/edit-nickname');
        if (mounted) _loadData();
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            UserAvatar(imageUrl: _user?['profileImageUrl'] as String?),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('프로필 편집',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 22),
          ],
        ),
      ),
    );
  }

  /// 요약 카드 — 보유/판매중/구매중을 한 장에. 숫자가 크고 라벨이 작다.
  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _SummaryStat(
              value: '$_totalCards',
              unit: '종',
              label: '보유 카드',
              onTap: () => context.push('/assets')),
          _statDivider(),
          _SummaryStat(
              value: '$_activeTrades',
              unit: '건',
              label: '판매중',
              onTap: () => context.push('/assets?tab=selling')),
          _statDivider(),
          _SummaryStat(
              value: '$_activeBuyOrders',
              unit: '건',
              label: '구매중',
              onTap: () => context.push('/assets?tab=buy')),
        ],
      ),
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 30, color: AppColors.dividerSoft);

}

/// 요약 카드의 스탯 1칸 — 숫자(크게)+단위(작게) / 라벨(아래 작게).
class _SummaryStat extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final VoidCallback? onTap;

  const _SummaryStat({
    required this.value,
    required this.unit,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  TextSpan(
                    text: unit,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
