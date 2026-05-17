import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/notifiers/asset_notifier.dart';
import '../../core/theme/app_colors.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    if (location == '/home' || location.startsWith('/home/')) return 0;
    if (location == '/trade-list' ||
        location.startsWith('/trade-list/') ||
        location == '/trades' ||
        location.startsWith('/trades/')) {
      return 1;
    }
    if (location == '/chat-list' || location.startsWith('/chat-list/')) return 2;
    if (location == '/profile' || location.startsWith('/profile/')) return 3;
    return 0;
  }

  Future<void> _openScanner() async {
    final result = await context.push<bool>('/scanner');
    if (result == true) AssetNotifier.instance.notifyChanged();
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    // resizeToAvoidBottomInset=false 만으로 FAB·푸터가 키보드 따라 안 올라옴.
    // 키보드 뜰 때 BottomNav를 null로 갈아끼우면 Scaffold 레이아웃 churn +
    // _BottomNav dispose가 검색 transition과 한 프레임에 겹쳐 lag 유발 → 가드 제거.
    return Scaffold(
      backgroundColor: AppColors.bg,
      resizeToAvoidBottomInset: false,
      body: widget.child,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _PressableFab(onPressed: _openScanner),
      bottomNavigationBar: _BottomNav(currentIndex: idx),
    );
  }
}

/// 4차-Round2: 누를 때 scale 0.96 + haptic + glow 미세 강조. Toss FAB 감각.
class _PressableFab extends StatefulWidget {
  final VoidCallback onPressed;
  const _PressableFab({required this.onPressed});

  @override
  State<_PressableFab> createState() => _PressableFabState();
}

class _PressableFabState extends State<_PressableFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _pressed = true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.blue,
            boxShadow: _pressed
                ? AppShadows.light(AppColors.blue)
                : AppShadows.glow(AppColors.blue),
          ),
          child: const Center(
            child: Icon(
              Icons.document_scanner_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNav extends StatefulWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

  @override
  State<_BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<_BottomNav> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnread();
  }

  @override
  void didUpdateWidget(covariant _BottomNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 챗 탭으로 진입할 때 + 챗 탭 외부로 나갈 때(룸 ↔ 다른 탭) 둘 다 reload.
    // ShellRoute가 location 변경마다 새 _BottomNav를 만들어 didUpdateWidget이
    // 라우트 전환 시점마다 호출되므로 unread badge가 stale되지 않음.
    if (widget.currentIndex != oldWidget.currentIndex) {
      _loadUnread();
    }
  }

  Future<void> _loadUnread() async {
    try {
      final res = await ApiClient.get('/api/chat/rooms');
      final rooms = (res['data'] as List?) ?? [];
      final total = rooms.fold<int>(
        0,
        (sum, r) => sum + ((r['unreadCount'] as num?)?.toInt() ?? 0),
      );
      if (!mounted) return;
      setState(() => _unreadCount = total);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomAppBar(
        color: AppColors.surfaceCard,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        elevation: 0,
        height: 72.0,
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                _NavItem(
                  activeIcon: Icons.home_rounded,
                  inactiveIcon: Icons.home_outlined,
                  label: '홈',
                  index: 0,
                  currentIndex: widget.currentIndex,
                  route: '/home',
                ),
                _NavItem(
                  activeIcon: Icons.swap_horiz,
                  inactiveIcon: Icons.swap_horiz,
                  label: '거래',
                  index: 1,
                  currentIndex: widget.currentIndex,
                  route: '/trade-list',
                ),
                const SizedBox(width: 64),
                _NavItem(
                  activeIcon: Icons.chat_bubble_rounded,
                  inactiveIcon: Icons.chat_bubble_outline_rounded,
                  label: '챗',
                  index: 2,
                  currentIndex: widget.currentIndex,
                  route: '/chat-list',
                  showBadge: _unreadCount > 0,
                ),
                _NavItem(
                  activeIcon: Icons.person_rounded,
                  inactiveIcon: Icons.person_outline_rounded,
                  label: 'MY',
                  index: 3,
                  currentIndex: widget.currentIndex,
                  route: '/profile',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  final int index;
  final int currentIndex;
  final String route;
  final bool showBadge;

  const _NavItem({
    required this.activeIcon,
    required this.inactiveIcon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.route,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => context.go(route),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedScale(
                  scale: selected ? 1.10 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  child: Icon(
                    selected ? activeIcon : inactiveIcon,
                    size: 28,
                    color: selected ? AppColors.blue : AppColors.textMuted,
                  ),
                ),
                if (showBadge)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: AppColors.red,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surfaceCard,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.blue : AppColors.textMuted,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            if (selected)
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.blue,
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
