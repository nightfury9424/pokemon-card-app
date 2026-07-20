import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../app/platform_app_config.dart';
import '../../core/theme/app_colors.dart';
import 'auth_service.dart';
import '../../core/widgets/app_error_toast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// null = idle, 'apple' / 'google' = 해당 provider 진행 중.
  String? _busy;
  bool get _loading => _busy != null;

  Future<void> _onGoogleLogin() async {
    setState(() => _busy = 'google');
    try {
      final requiresOnboarding = await AuthService.loginWithGoogle()
          .timeout(const Duration(seconds: 90)); // 무한 스피너 방지(App Store 2.1a)
      if (!mounted) return;
      context.go(requiresOnboarding ? '/onboarding' : '/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      if (e.toString().contains('취소')) return; // 사용자 취소는 조용히
      AppErrorToast.show(context, _loginErrorMessage(e));
    }
  }

  Future<void> _onAppleLogin() async {
    setState(() => _busy = 'apple');
    try {
      final requiresOnboarding = await AuthService.loginWithApple()
          .timeout(const Duration(seconds: 90)); // 무한 스피너 방지(App Store 2.1a)
      if (!mounted) return;
      context.go(requiresOnboarding ? '/onboarding' : '/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = null);
      // 취소는 조용히 무시.
      if (e.toString().contains('취소')) return;
      AppErrorToast.show(context, _loginErrorMessage(e));
    }
  }

  /// 예외 → 사용자 친화 메시지. 백엔드 응답 message(탈퇴 등) 우선, 네트워크/타임아웃은 안내문.
  /// (raw DioException 노출 방지 — App Store 심사서 지적된 "DioException..." 메시지 대응)
  String _loginErrorMessage(Object e) {
    if (e is TimeoutException) {
      return '로그인이 지연되고 있어요. 네트워크 확인 후 다시 시도해주세요.';
    }
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map &&
          data['message'] is String &&
          (data['message'] as String).trim().isNotEmpty) {
        return data['message'] as String; // 백엔드 메시지(예: 탈퇴 후 3개월 재가입 제한)
      }
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return '네트워크 연결이 원활하지 않아요. 잠시 후 다시 시도해주세요.';
        default:
          break;
      }
    }
    return '로그인에 실패했어요. 잠시 후 다시 시도해주세요.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // ★Toss restyle: 플랫 배경 (그라데이션/글로우 blob 제거)
          const Positioned.fill(
            child: ColoredBox(color: AppColors.bg),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  // 히어로 로고
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Image.asset(
                      'assets/app_icon/logo.png',
                      width: 96,
                      height: 96,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '포켓폴리오',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '내 포켓몬 카드 자산을 한눈에',
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(flex: 2),
                  // 가치 제안
                  _feature(Icons.document_scanner_rounded, '카메라로 카드 스캔·자동 인식'),
                  const SizedBox(height: 14),
                  _feature(Icons.trending_up_rounded, '실시간 카드 시세 추적'),
                  const SizedBox(height: 14),
                  _feature(Icons.donut_large_rounded, '내 컬렉션 포트폴리오 관리'),
                  const SizedBox(height: 14),
                  _feature(Icons.swap_horiz_rounded, '안전한 카드 거래'),
                  const Spacer(flex: 3),
                  // Apple — 다크모드 HIG: 흰색 솔리드 (primary).
                  // 플랫폼 분리(2026-07-20): Android 는 미노출(공백도 안 남김) — AppConfig 로만 통제.
                  // 인증 서비스·백엔드 로직은 보존(렌더링만 분기).
                  if (AppConfig.current.showAppleSignIn) ...[
                    _socialButton(
                      onPressed: _onAppleLogin,
                      busy: _busy == 'apple',
                      background: Colors.white,
                      foreground: Colors.black,
                      border: null,
                      icon: const Icon(Icons.apple, size: 22, color: Colors.black),
                      label: 'Apple로 시작하기',
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Google — 다크 surface (secondary)
                  _socialButton(
                    onPressed: _onGoogleLogin,
                    busy: _busy == 'google',
                    background: AppColors.surfaceElevated,
                    foreground: AppColors.textPrimary,
                    border: AppColors.divider,
                    icon: Image.network(
                      'https://www.google.com/favicon.ico',
                      width: 20,
                      height: 20,
                      errorBuilder: (context, error, stack) =>
                          const Icon(Icons.g_mobiledata, size: 24, color: Colors.white),
                    ),
                    label: 'Google로 시작하기',
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '본 앱은 비공식 팬 앱이며, 모든 포켓몬 관련 권리는 각 권리자에게 있습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '로그인하면 이용약관 및 개인정보처리방침에 동의하게 됩니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted, height: 1.4),
                  ),
                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(IconData icon, String text) => Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider, width: 1),
            ),
            child: Icon(icon, size: 19, color: AppColors.blueLight),
          ),
          const SizedBox(width: 14),
          Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      );

  Widget _socialButton({
    required Future<void> Function() onPressed,
    required bool busy,
    required Color background,
    required Color foreground,
    required Color? border,
    required Widget icon,
    required String label,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: border != null ? BorderSide(color: border, width: 1) : BorderSide.none,
          ),
          elevation: 0,
        ),
        child: busy
            ? SizedBox(
                width: 21,
                height: 21,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: foreground),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
