import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/login_screen.dart';
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
import '../../features/chat/chat_screen.dart';
import '../../features/chat/chat_room_screen.dart';
import '../../features/trade/trade_list_screen.dart';
import '../../features/trade/trade_detail_screen.dart';
import '../../features/trade/trade_create_screen.dart';
import '../storage/token_storage.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  redirect: (context, state) async {
    // TODO: 개발 중 인증 가드 비활성화
    return null;
    // final isLoggedIn = await TokenStorage.exists();
    // final isLoginPage = state.uri.path == '/login';
    // if (!isLoggedIn && !isLoginPage) return '/login';
    // if (isLoggedIn && isLoginPage) return '/home';
    // return null;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/scanner', builder: (_, __) => const ScannerScreen()),
    GoRoute(
      path: '/card/:cardId',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        // extra가 {'myAsset': ...} 형태이면 분리, 아니면 cardData로 취급
        final myAsset = extra?['myAsset'] as Map<String, dynamic>?;
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
        final extra = state.extra as Map<String, dynamic>?;
        return ProductCardsScreen(
          productId: state.pathParameters['productId']!,
          productName: extra?['productName'] as String?,
          seriesName: extra?['seriesName'] as String?,
        );
      },
    ),
    GoRoute(path: '/assets', builder: (_, __) => const AssetScreen()),
    GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
    GoRoute(
      path: '/my-trades',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return TradeListScreen(
          filterSellerId: extra?['sellerId'] as String?,
          title: '내 판매 항목',
        );
      },
    ),
    GoRoute(path: '/packs', builder: (_, __) => const PacksScreen()),
    GoRoute(
      path: '/trades',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return TradeListScreen(
          filterCardId: extra?['cardId'] as String?,
          filterCardName: extra?['cardName'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/trades/create',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return TradeCreateScreen(
          cardId: extra['cardId'] as String? ?? '',
          cardName: extra['cardName'] as String?,
          rarity: extra['rarity'] as String?,
          imageUrl: extra['imageUrl'] as String?,
        );
      },
    ),
    GoRoute(
      path: '/trades/:tradeId',
      builder: (context, state) => TradeDetailScreen(
        tradeId: state.pathParameters['tradeId']!,
      ),
    ),
    GoRoute(
      path: '/chat/:roomId',
      builder: (context, state) => ChatRoomScreen(
        roomId: state.pathParameters['roomId']!,
        roomInfo: state.extra as Map<String, dynamic>? ?? {},
      ),
    ),
    GoRoute(path: '/grading/capture', builder: (_, __) => const GradingCaptureScreen()),
    GoRoute(
      path: '/grading/result',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return GradingResultScreen(photos: extra['photos'] as List<File>);
      },
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
        GoRoute(path: '/prices', builder: (_, __) => const PriceScreen()),
        GoRoute(path: '/grading', builder: (_, __) => const GradingScreen()),
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      ],
    ),
  ],
);
