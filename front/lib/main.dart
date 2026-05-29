import 'package:flutter/material.dart';
import 'core/auth/auth_state.dart';
import 'core/network/api_client.dart';
import 'core/router/app_router.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/app_error_toast.dart';
import 'features/admin/admin_api.dart';

// 라우터/토스트 context 진입용 전역 키.
// 사용자 정책: Material SnackBar 금지 — AppSuccessToast / AppErrorToast 가운데 fade로 통일.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ApiClient 전역 에러 핸들러 — 401/5xx/네트워크 끊김 시 통일된 AppErrorToast (가운데 ⚠ fade).
  // 이전: Material SnackBar (빨간 띠) → 사용자 정책 위반(통일 안 됨). AppErrorToast로 교체.
  ApiClient.setErrorHandler((info) {
    final ctx = rootScaffoldMessengerKey.currentContext;
    if (ctx != null) {
      AppErrorToast.show(ctx, info.message);
    }
    if (info.isAuthError) {
      // 토큰 만료 → 다음 요청 자동 안 보내도록 토큰 폐기 + 라우터 상태 갱신
      TokenStorage.delete();
      AuthState.instance.markLoggedOut();
    }
  });

  await AuthState.instance.bootstrap();
  // 2026-05-29 admin Stage 0 — 로그인 사용자 한정 /api/admin/whoami probe (403 silent).
  // 비-로그인은 호출 자체 skip — JwtAuthFilter 가 401 returning, 메뉴 어차피 안 보임.
  if (AuthState.instance.loggedIn) {
    // unawaited — bootstrap 차단 X, 결과는 AuthState 통해 ProfileScreen rebuild.
    AdminApi.probeIsAdmin();
  }
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
