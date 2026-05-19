import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/onboarding_screen.dart';
import '../../features/grading/grading_screen.dart';
import '../../features/grading/grading_capture_screen.dart';
import '../../features/grading/grading_result_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/card/card_detail_screen.dart';
import '../../features/card/product_cards_screen.dart';
import '../../features/asset/asset_screen.dart';
import '../../features/price/price_screen.dart';
import '../../features/packs/packs_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/favorites_screen.dart';
import '../../features/profile/edit_nickname_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chat_room_screen.dart';
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
    GoRoute(
      path: '/scanner',
      builder: (_, state) {
        final expected = state.uri.queryParameters['expectedCardId'];
        return ScannerScreen(expectedCardId: expected);
      },
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
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : <String, dynamic>{};
        return TradeCreateScreen(
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
      builder: (context, state) => ChatRoomScreen(
        roomId: state.pathParameters['roomId']!,
        roomInfo: state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : {},
      ),
    ),
    GoRoute(path: '/grading', builder: (_, _) => const GradingScreen()),
    GoRoute(
      path: '/grading/capture',
      builder: (context, state) {
        final extra = state.extra is Map
            ? Map<String, dynamic>.from(state.extra as Map)
            : <String, dynamic>{};
        return GradingCaptureScreen(
          assetId: extra['assetId'] as String?,
          cardId: extra['cardId'] as String?,
          cardName: extra['cardName'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/grading/result',
      builder: (context, state) {
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
