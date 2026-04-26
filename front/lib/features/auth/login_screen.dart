import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;

  Future<void> _onKakaoLogin() async {
    setState(() => _loading = true);
    try {
      await AuthService.loginWithKakao();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('카카오 로그인 실패: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // 로고 영역
              const Icon(Icons.catching_pokemon, size: 80, color: Color(0xFFE53935)),
              const SizedBox(height: 16),
              const Text(
                '포켓몬 카드',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Text(
                '자산 관리',
                style: TextStyle(fontSize: 18, color: Colors.white70),
              ),
              const Spacer(flex: 3),
              // 카카오 로그인 버튼
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _onKakaoLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFEE500),
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('💬', style: TextStyle(fontSize: 18)),
                            SizedBox(width: 8),
                            Text(
                              '카카오로 시작하기',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // 개발용 테스트 로그인 (에뮬레이터 테스트 전용)
              TextButton(
                onPressed: _loading ? null : _onDevLogin,
                child: const Text(
                  '[DEV] 테스트 로그인',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onDevLogin() async {
    setState(() => _loading = true);
    final success = await AuthService.devLogin();
    if (!mounted) return;
    setState(() => _loading = false);

    if (success) {
      context.go('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('개발 로그인 실패')),
      );
    }
  }
}
