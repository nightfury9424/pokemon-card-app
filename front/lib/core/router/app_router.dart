import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/grading/grading_screen.dart';
import '../../features/grading/grading_capture_screen.dart';
import '../../features/grading/grading_result_screen.dart';
import '../../features/grading/grading_asset_select_screen.dart';
import '../../features/grading/asset_grading_detail_screen.dart';
import '../constants/feature_flags.dart';
import '../theme/app_colors.dart';
import '../../features/shell/main_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/card/card_detail_screen.dart';
import '../../features/card/product_cards_screen.dart';
import '../../features/asset/asset_screen.dart';
import '../../features/asset/dex/dex_detail_screen.dart';
import '../../features/price/price_screen.dart';
import '../../features/packs/packs_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/favorites_screen.dart';
import '../../features/profile/edit_nickname_screen.dart';
import '../../features/profile/blocked_users_screen.dart';
import '../../features/profile/report_history_screen.dart';
import '../../features/profile/inquiry_history_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chat_room_screen.dart';
import '../../features/legal/terms_of_service_screen.dart';
import '../../features/legal/privacy_policy_screen.dart';
import '../../features/legal/customer_support_screen.dart';
import '../../features/legal/inquiry_category.dart';
import '../../features/legal/inquiry_compose_screen.dart';
import '../../features/trade/trade_list_screen.dart';
import '../../features/trade/trade_detail_screen.dart';
import '../../features/trade/trade_create_screen.dart';
import '../auth/auth_state.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  refreshListenable: AuthState.instance,
  redirect: (context, state) {
    final auth = AuthState.instance;
    if (!auth.ready) return null;

    final path = state.uri.path;
    final isLoginPage = path == '/login';
    final isOnboardingPage = path == '/onboarding';

    if (!auth.loggedIn) {
      return isLoginPage ? null : '/login';
    }
    if (!auth.onboarded) {
      return isOnboardingPage ? null : '/onboarding';
    }
    if (isLoginPage || isOnboardingPage) return '/home';
    return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(path: '/profile/edit-nickname', builder: (_, _) => const EditNicknameScreen()),
    GoRoute(path: '/profile/blocked-users', builder: (_, _) => const BlockedUsersScreen()),
    GoRoute(path: '/profile/reports', builder: (_, _) => const ReportHistoryScreen()),
    GoRoute(path: '/profile/inquiries', builder: (_, _) => const InquiryHistoryScreen()),
    GoRoute(path: '/legal/terms', builder: (_, _) => const TermsOfServiceScreen()),
    GoRoute(path: '/legal/privacy', builder: (_, _) => const PrivacyPolicyScreen()),
    GoRoute(path: '/support', builder: (_, _) => const CustomerSupportScreen()),
    // 카테고리별 문의 작성 — 잘못된 key면 카테고리 list로 폴백.
    GoRoute(
      path: '/support/inquiry/:category',
      builder: (_, state) {
        final cat = InquiryCategory.fromKey(state.pathParameters['category']);
        if (cat == null) return const CustomerSupportScreen();
        return InquiryComposeScreen(category: cat);
      },
    ),
    GoRoute(
      path: '/scanner',
      builder: (_, state) {
        final expected = state.uri.queryParameters['expectedCardId'];
        return ScannerScreen(expectedCardId: expected);
      },
    ),
    // 2026-05-29 Phase B — 도감 시리즈 상세.
    GoRoute(
      path: '/dex/:productId',
      builder: (_, state) => DexDetailScreen(
        productId: state.pathParameters['productId']!,
      ),
    ),
    GoRoute(
      path: '/card/:cardId',
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : null;
        // extra가 {'myAsset': ...} 형태이면 분리, 아니면 cardData로 취급
        final myAssetRaw = extra?['myAsset'];
        final myAsset = myAssetRaw is Map
            ? Map<String, dynamic>.from(myAssetRaw)
            : null;
        final cardData = myAsset != null ? null : extra;
        return CardDetailScreen(
          cardId: state.pathParameters['cardId']!,
          cardData: cardData,
          myAsset: myAsset,
        );
      },
    ),
    GoRoute(
      path: '/product/:productId',
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : null;
        return ProductCardsScreen(
          productId: state.pathParameters['productId']!,
          productName: extra?['productName'] as String?,
          seriesName: extra?['seriesName'] as String?,
        );
      },
    ),
    GoRoute(path: '/prices', builder: (_, _) => const PriceScreen()),
    GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),
    GoRoute(
      path: '/my-trades',
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : null;
        return TradeListScreen(
          filterSellerId: extra?['sellerId'] as String?,
          title: '내 판매 항목',
        );
      },
    ),
    GoRoute(
      path: '/trades',
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : null;
        return TradeListScreen(
          filterCardId: extra?['cardId'] as String?,
          filterCardName: extra?['cardName'] as String?,
        );
      },
    ),
    GoRoute(path: '/packs', builder: (_, _) => const PacksScreen()),
    GoRoute(
      path: '/trades/create',
      // 판매글 등록 = 아래서 위로 슬라이드업 모달 (UX 간소화).
      pageBuilder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : <String, dynamic>{};
        return CustomTransitionPage<void>(
          key: state.pageKey,
          opaque: false,
          barrierColor: Colors.black54,
          barrierDismissible: true,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 240),
          transitionsBuilder: (context, animation, _, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.82,
            minChildSize: 0.55,
            maxChildSize: 0.97,
            expand: false,
            snap: true,
            snapSizes: const [0.82, 0.97],
            builder: (context, scrollController) => ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              child: TradeCreateScreen(
                cardId: extra['cardId'] as String? ?? '',
                cardName: extra['cardName'] as String?,
                rarity: extra['rarity'] as String?,
                imageUrl: extra['imageUrl'] as String?,
                assetId: extra['assetId'] as String?,
                cardStatus: extra['cardStatus'] as String?,
                estimatedGrade: extra['estimatedGrade'] is num
                    ? (extra['estimatedGrade'] as num).toDouble()
                    : double.tryParse('${extra['estimatedGrade'] ?? ''}'),
                gradingCompany: extra['gradingCompany'] as String?,
                gradeValue: extra['gradeValue'] as String?,
                certNumber: extra['certNumber'] as String?,
                defaultPrice: extra['defaultPrice'] is num
                    ? (extra['defaultPrice'] as num).toInt()
                    : int.tryParse('${extra['defaultPrice'] ?? ''}'),
                sheetScrollController: scrollController,
              ),
            ),
          ),
        );
      },
    ),
    GoRoute(
      path: '/trades/:tradeId',
      builder: (context, state) =>
          TradeDetailScreen(tradeId: state.pathParameters['tradeId']!),
    ),
    GoRoute(
      path: '/chat/:roomId',
      // Phase 1 hotfix#9: hotfix#8 FadeTransition 도 animation 진행 중 이전 trade_detail
      // 이 sub-stack에 visible 한 문제. fade 부드러움 < 잔상 즉시 제거 우선 → NoTransitionPage
      // (transition 0ms). 클릭 즉시 chat_room 전체 표시, 좌측 trade_detail 관심 버튼 잔상
      // 완전 제거. 빈 spinner 첫 frame은 그대로지만 fade 중에도 동일 — 이전 화면 노출이
      // 더 큰 회귀라 transition 자체 폐기가 안전.
      pageBuilder: (context, state) {
        final roomInfo = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : <String, dynamic>{};
        return NoTransitionPage<void>(
          key: state.pageKey,
          child: ChatRoomScreen(
            roomId: state.pathParameters['roomId']!,
            roomInfo: roomInfo,
          ),
        );
      },
    ),
    // Hotfix 10-1: AI 그레이딩 5 route 모두 feature flag 가드.
    // enableAiGrading=false → _GradingDisabledScreen 으로 redirect.
    // route 자체 보존 (deep link / 직접 navigate 안전).
    GoRoute(
        path: '/grading',
        builder: (_, _) => FeatureFlags.enableAiGrading
            ? const GradingScreen()
            : const _GradingDisabledScreen()),
    GoRoute(
      path: '/grading/select-asset',
      builder: (_, _) => FeatureFlags.enableAiGrading
          ? const GradingAssetSelectScreen()
          : const _GradingDisabledScreen(),
    ),
    GoRoute(
      path: '/grading/saved/:assetId',
      builder: (context, state) => FeatureFlags.enableAiGrading
          ? AssetGradingDetailScreen(assetId: state.pathParameters['assetId']!)
          : const _GradingDisabledScreen(),
    ),
    GoRoute(
      path: '/grading/capture',
      // Hotfix 10-2 v2 (Plan E): mode='card_verify' (또는 legacy 'sell_photo') 는 enableAiGrading=false 여도 허용.
      // 그 외 (analyze legacy) 는 enableAiGrading=true 일 때만 허용.
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : <String, dynamic>{};
        final mode = extra['mode'] as String? ?? 'analyze';
        final isCardVerify = mode == 'card_verify' || mode == 'sell_photo';
        if (!isCardVerify && !FeatureFlags.enableAiGrading) {
          return const _GradingDisabledScreen();
        }
        return GradingCaptureScreen(
          assetId: extra['assetId'] as String?,
          cardId: extra['cardId'] as String?,
          cardName: extra['cardName'] as String?,
          mode: mode,
        );
      },
    ),
    GoRoute(
      path: '/grading/result',
      builder: (context, state) {
        if (!FeatureFlags.enableAiGrading) return const _GradingDisabledScreen();
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : <String, dynamic>{};
        return GradingResultScreen(
          photos: (extra['photos'] is List
              ? List<File>.from(extra['photos'] as List)
              : <File>[]),
          assetId: extra['assetId'] as String?,
          cardId: extra['cardId'] as String?,
          cardName: extra['cardName'] as String?,
          frameRect: extra['frameRect'] is Map
              ? Map<String, double>.from(extra['frameRect'] as Map)
              : null,
        );
      },
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(
          path: '/assets',
          builder: (_, state) {
            final tab = state.uri.queryParameters['tab'];
            final idx = switch (tab) {
              'buy' => 2,
              'selling' => 1,
              _ => 0,
            };
            return AssetScreen(initialTabIndex: idx);
          },
        ),
        GoRoute(
          path: '/trade-list',
          builder: (_, _) => const TradeListScreen(),
        ),
        GoRoute(path: '/chat-list', builder: (_, _) => const ChatScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      ],
    ),
  ],
);

// Hotfix 10-1: AI 그레이딩 비활성 시 5 route 모두 진입 차단 placeholder.
// 신고 진행상황 처럼 "준비 중" 안내. 코드/route 보존, 진입만 막음.
class _GradingDisabledScreen extends StatelessWidget {
  const _GradingDisabledScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('AI 그레이딩',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16,
                fontWeight: FontWeight.w600)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Icon(Icons.auto_awesome_rounded, color: AppColors.textMuted, size: 48),
            SizedBox(height: 16),
            Text('AI 그레이딩은 현재 준비 중입니다',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text(
              '더 정확한 카드 상태 분석을 위해 개선 중입니다.\n'
              '베타 사용자 피드백을 바탕으로 빠르게 출시할 예정입니다.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ]),
        ),
      ),
    );
  }
}
