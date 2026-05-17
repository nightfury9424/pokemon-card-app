import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _onGoogleLogin() async {
    setState(() => _loading = true);
    try {
      final requiresOnboarding = await AuthService.loginWithGoogle();
      if (!mounted) return;
      context.go(requiresOnboarding ? '/onboarding' : '/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('구글 로그인 실패: $e'), duration: const Duration(seconds: 4)),
      );
    }
  }

  Future<void> _onDevLogin() async {
    setState(() => _loading = true);
    final requiresOnboarding = await AuthService.devLogin();
    if (!mounted) return;
    setState(() => _loading = false);
    if (requiresOnboarding == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('개발 로그인 실패')),
      );
      return;
    }
    context.go(requiresOnboarding ? '/onboarding' : '/home');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.blue, Color(0xFF1040A0)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.catching_pokemon, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              const Text('포켓몬 카드',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('자산 관리',
                  style: TextStyle(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
              const Spacer(flex: 3),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _onGoogleLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.blue))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://www.google.com/favicon.ico',
                              width: 20, height: 20,
                              errorBuilder: (_, __, ___) => const Icon(Icons.login, size: 20),
                            ),
                            const SizedBox(width: 10),
                            const Text('Google로 시작하기',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loading ? null : _onDevLogin,
                child: const Text('[DEV] 테스트 로그인',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
