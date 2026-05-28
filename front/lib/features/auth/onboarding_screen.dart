import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_state.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/user_avatar.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _checking = false;
  bool? _available;
  String? _validationError;
  bool _submitting = false;
  int _requestToken = 0;
  // 회원가입 시 필수 동의 — 한국 개인정보보호법 + Apple App Review.
  // MVP는 프론트 체크박스만 (체크 전엔 "시작하기" 비활성). 백엔드 동의 시각 기록은 v1.1.
  bool _agreedTos = false;
  bool _agreedPrivacy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _available = null;
      _validationError = null;
    });
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _check(trimmed));
  }

  Future<void> _check(String value) async {
    final token = ++_requestToken;
    setState(() => _checking = true);
    try {
      final res = await ApiClient.get(
        '/api/users/nickname/check',
        params: {'value': value},
      );
      if (!mounted || token != _requestToken) return;
      final available = (res['data']?['available'] as bool?) ?? false;
      setState(() {
        _checking = false;
        _available = available;
        _validationError = null;
      });
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _checking = false;
        _available = false;
        _validationError = _extractMessage(e);
      });
    }
  }

  Future<void> _submit() async {
    final nickname = _controller.text.trim();
    if (nickname.isEmpty || _available != true) return;
    setState(() => _submitting = true);
    try {
      await ApiClient.put('/api/users/onboarding', {'nickname': nickname});
      await TokenStorage.setOnboarded(true);
      AuthState.instance.markOnboarded();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationError = _extractMessage(e);
        _available = false;
      });
    }
  }

  /// 백엔드 envelope의 specific 사유 노출 — NicknameValidator가 ResponseStatusException으로
  /// "닉네임은 2~15자여야 합니다" / "사용할 수 없는 닉네임입니다" 등 명시 사유 던짐.
  /// ApiClient.get → DioException → response.data['message'] 추출이 정공법. toString 파싱은 fallback.
  String _extractMessage(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['message'] is String) {
        final msg = (data['message'] as String).trim();
        if (msg.isNotEmpty) return msg;
      }
    }
    final s = e.toString();
    final idx = s.indexOf('"message"');
    if (idx >= 0) {
      final start = s.indexOf('"', idx + 9);
      final end = s.indexOf('"', start + 1);
      if (start >= 0 && end > start) return s.substring(start + 1, end);
    }
    return '잠시 후 다시 시도해주세요';
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _available == true && !_submitting && _agreedTos && _agreedPrivacy;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              const Text(
                '닉네임을 정해주세요',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '2~15자, 다른 사용자에게 보여집니다',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 36),
              const Center(child: UserAvatar(size: 96)),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                maxLength: 15,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => canSubmit ? _submit() : null,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: '닉네임',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.surfaceCard,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.blue, width: 1.5),
                  ),
                  suffixIcon: _checking
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.blue,
                            ),
                          ),
                        )
                      : _available == true
                          ? const Icon(Icons.check_circle, color: AppColors.green)
                          : _available == false
                              ? const Icon(Icons.cancel, color: AppColors.red)
                              : null,
                ),
              ),
              if (_validationError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _validationError!,
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ] else if (_available == true) ...[
                const SizedBox(height: 6),
                const Text(
                  '사용 가능한 닉네임입니다',
                  style: TextStyle(color: AppColors.green, fontSize: 13),
                ),
              ],
              const SizedBox(height: 24),
              // 회원가입 필수 동의 (한국 개인정보보호법 + Apple App Review). 둘 다 체크돼야 "시작하기" 활성.
              _ConsentCheckbox(
                checked: _agreedTos,
                onChanged: (v) => setState(() => _agreedTos = v),
                label: '이용약관에 동의합니다 (필수)',
                onLinkTap: () => context.push('/legal/terms'),
              ),
              const SizedBox(height: 8),
              _ConsentCheckbox(
                checked: _agreedPrivacy,
                onChanged: (v) => setState(() => _agreedPrivacy = v),
                label: '개인정보처리방침에 동의합니다 (필수)',
                onLinkTap: () => context.push('/legal/privacy'),
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.surfaceCard,
                    disabledForegroundColor: AppColors.textMuted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          '시작하기',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// 가입 동의 체크박스 row — 라벨 + "보기" 링크. 필수 동의(_agreedTos/_agreedPrivacy)에만 사용.
class _ConsentCheckbox extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String label;
  final VoidCallback onLinkTap;

  const _ConsentCheckbox({
    required this.checked,
    required this.onChanged,
    required this.label,
    required this.onLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: AppColors.blue,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!checked),
            behavior: HitTestBehavior.opaque,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: onLinkTap,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            '보기',
            style: TextStyle(
              color: AppColors.blue,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
