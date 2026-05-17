import 'package:flutter/material.dart';
import 'core/auth/auth_state.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_colors.dart';

// SnackBar 표시 + 401 시 로그인 화면 이동을 위한 전역 키 (REFACTOR_2026-05-12.md 3차-A)
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ApiClient 전역 에러 핸들러 등록 — 401/5xx/네트워크 끊김 시 자동 SnackBar
  ApiClient.setErrorHandler((info) {
    final messenger = rootScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(info.message),
      backgroundColor: info.isAuthError
          ? Colors.deepOrange.shade700
          : (info.isServerError || info.isNetworkError ? Colors.red.shade700 : Colors.grey.shade700),
      duration: Duration(seconds: info.isAuthError ? 4 : 3),
    ));
    if (info.isAuthError) {
      // 토큰 만료 → 다음 요청 자동 안 보내도록 토큰 폐기 + 라우터 상태 갱신
      TokenStorage.delete();
      AuthState.instance.markLoggedOut();
    }
  });

  await AuthState.instance.bootstrap();
  runApp(const PokemonCardApp());
}

class PokemonCardApp extends StatelessWidget {
  const PokemonCardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '포켓몬 카드',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE53935),
          surface: Color(0xFF16213E),
        ),
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          backgroundColor: AppColors.bg,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      routerConfig: appRouter,
    );
  }
}
