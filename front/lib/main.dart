import 'package:flutter/material.dart';
import 'core/auth/auth_state.dart';
import 'core/network/api_client.dart';
import 'core/notifications/chat_socket_service.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/router/app_router.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/app_error_toast.dart';

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
  // FCM 푸시 init (GoogleService-Info.plist 없으면 guard로 무해). 권한 요청 비동기 — runApp 블록 X.
  // init 완료(Firebase+권한+APNs) 후, 이미 로그인 상태면 토큰 등록(앱 재시작 케이스).
  // 미로그인이면 로그인 흐름(auth_service)에서 registerToken 호출.
  PushNotificationService.init().then((_) {
    if (AuthState.instance.loggedIn) {
      PushNotificationService.registerToken();
    }
  });
  // STOMP 전역 연결은 FCM init 완료에 의존하지 않게 분리 — init 지연/실패해도 채팅 실시간 보장.
  if (AuthState.instance.loggedIn) {
    ChatSocketService.connect();
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
      // 해상도/접근성 대응: iOS Dynamic Type(설정>글자 크게) 시 고정 height 레이아웃(버튼·칩·
      // 가격 행 등) 오버플로 방지 — 텍스트 배율 상한을 1.15 로 clamp. 기본(1.0) 사용자는 무변화,
      // 과도하게 키운 경우만 1.15 로 제한. (전 화면 일괄 적용)
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15),
          ),
          child: child!,
        );
      },
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
          // Hotfix 10-3: Material3 의 scroll-under tint 비활성 — 전 화면 AppBar 가
          // 스크롤 시 surfaceTint overlay 로 색이 살짝 변하는 버그 차단.
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
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
