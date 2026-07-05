import 'package:flutter/material.dart';
import 'core/auth/auth_state.dart';
import 'core/network/api_client.dart';
import 'core/network/api_error_policy.dart';
import 'core/notifications/chat_socket_service.dart';
import 'core/notifications/push_notification_service.dart';
import 'core/notifiers/home_session_cache.dart';
import 'core/config/maintenance_gate.dart';
import 'core/config/version_gate.dart';
import 'core/router/app_router.dart';
import 'core/storage/token_storage.dart';
import 'core/theme/app_colors.dart';
import 'core/widgets/app_error_toast.dart';
import 'core/widgets/auth_image.dart';

// 라우터/토스트 context 진입용 전역 키.
// 사용자 정책: Material SnackBar 금지 — AppSuccessToast / AppErrorToast 가운데 fade로 통일.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ApiClient 전역 에러 핸들러 — 401/5xx/네트워크 끊김 시 통일된 AppErrorToast (가운데 ⚠ fade).
  // 이전: Material SnackBar (빨간 띠) → 사용자 정책 위반(통일 안 됨). AppErrorToast로 교체.
  ApiClient.setErrorHandler((info) {
    // ★정책으로 결정(ApiErrorPolicy): 인증·계정 lifecycle 은 silent 여부와 무관하게 항상,
    //   전역 토스트는 silent(suppressToast)면 억제. silent 화면은 도메인 오류를 인라인 처리.
    final action = ApiErrorPolicy.decide(info);
    // 정지 계정 — 게이트로(토스트 없음).
    if (action.markSuspended) {
      AuthState.instance.markSuspended();
      return;
    }
    if (action.showToast) {
      final ctx = rootScaffoldMessengerKey.currentContext;
      if (ctx != null) {
        AppErrorToast.show(ctx, info.message);
      }
    }
    if (action.clearAuthSession) {
      // 토큰 만료 → 토큰 폐기 + 세션 캐시 초기화 + 로그아웃 전환(silent 여도 항상).
      TokenStorage.delete();
      HomeSessionCache.clear(); // 재로그인 시 이전 유저 자산/포트폴리오 홈 잔존 방지(logout 경로와 동일)
      // ★401 silent 로그아웃도 명시 logout()과 동일하게 private 이미지 캐시 클리어(보안).
      // 메모리는 즉시(동기) 비우고 디스크는 비동기 emptyCache — 콜백이 동기라 fire-and-forget.
      clearAuthImageCache();
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
          // 전역 키보드 dismiss — 입력 외 빈 곳 탭 시 포커스 해제(키보드 내림).
          // translucent: 자식(버튼/TextField/스크롤)의 제스처는 그대로 — 자식이 안 먹은 탭만 여기로.
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            // 점검 게이트 — maintenance.json(백엔드 독립) 기반 전역 점검 화면.
            // 그 안쪽에 버전 게이트 중첩 — 우선순위 점검 > HARD > SOFT 업데이트.
            child: MaintenanceGate(child: VersionGate(child: child!)),
          ),
        );
      },
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          // #13 root fix: primary 가 빨강(0xFFE53935)이라 색 미지정 위젯의 ripple/splash/indicator/
          //   기본 RefreshIndicator(#10)가 전부 빨강으로 번졌음 → 브랜드 블루로. 명시적 AppColors.red(매수/하트)는 무관.
          primary: AppColors.blue,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.bg,
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
