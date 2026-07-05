import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_state.dart';
import '../../core/network/api_client.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/user_avatar.dart';
import 'auth_service.dart';
import 'onboarding_draft.dart';

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
  // 선택 동의 — 스캔한 실카드 이미지 수집·활용(서비스 개선·카드 이미지 품질 향상).
  // 비필수라 시작하기를 막지 않음. 거부해도 스캔 기능은 정상 동작(업로드만 skip).
  bool _agreedScanImages = false;
  // 만 14세 self-declared 게이트 (한국 PIPA). null=미응답, true=14세 이상, false=미만(차단).
  bool? _ageOver14;

  @override
  void initState() {
    super.initState();
    // background/resume 또는 라우터 재계산으로 State 재생성돼도 입력 유지 — draft 에서 복원.
    final d = OnboardingDraft.instance;
    _ageOver14 = d.ageOver14;
    _agreedTos = d.agreedTos;
    _agreedPrivacy = d.agreedPrivacy;
    _agreedScanImages = d.agreedScanImages;
    if (d.nickname.isNotEmpty) {
      _controller.text = d.nickname;
      _check(d.nickname); // 닉네임 가용성 재검증 → '사용 가능' 상태 복원
    }
  }

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
    OnboardingDraft.instance.nickname = trimmed;
    if (trimmed.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _check(trimmed));
  }

  // B2-21: 전체 동의에 만14세 확인 포함.
  bool get _allAgreed =>
      _ageOver14 == true && _agreedTos && _agreedPrivacy && _agreedScanImages;

  /// 전체 동의 토글 — 만14세+3개 일괄 설정(+draft). 개별 해제 가능(PIPA: 선택 강제 아님).
  void _setAllConsents(bool v) {
    setState(() {
      _ageOver14 = v ? true : null;
      _agreedTos = v;
      _agreedPrivacy = v;
      _agreedScanImages = v;
      final d = OnboardingDraft.instance;
      d.ageOver14 = _ageOver14;
      d.agreedTos = v;
      d.agreedPrivacy = v;
      d.agreedScanImages = v;
    });
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
      // scanImageConsent: 선택 동의. 백엔드 미수용 필드는 Jackson 이 무시(forward-compat) —
      // 스캔 이미지 파이프라인 구축 시 User 필드로 영속화.
      await ApiClient.put('/api/users/onboarding',
          {'nickname': nickname, 'isOver14': true, 'scanImageConsent': _agreedScanImages});
      await TokenStorage.setOnboarded(true);
      OnboardingDraft.instance.clear();
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

  Future<void> _onBlockedLogout() async {
    await AuthService.logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          // B2-21: 만14세 게이트를 별도 화면에서 약관 동의 체크박스로 통합 → 본 폼 직행.
          child: _buildNicknameForm(),
        ),
      ),
    );
  }

  /// 만 14세 이상 자가확인 — 미만 선택 시 차단 화면으로.
  Widget _buildAgeGate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 72),
        const Icon(Icons.verified_user_outlined, color: AppColors.blueLight, size: 48),
        const SizedBox(height: 24),
        const Text(
          '만 14세 이상이신가요?',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '관련 법령에 따라 가입 시 연령 확인이 필요해요.\n생년월일은 저장하지 않으며, 확인 여부만 기록됩니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const Spacer(),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: () => setState(() {
              _ageOver14 = true;
              OnboardingDraft.instance.ageOver14 = true;
            }),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('만 14세 이상입니다',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _ageOver14 = false;
            OnboardingDraft.instance.ageOver14 = false;
          }),
          child: const Text('만 14세 미만입니다',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 만 14세 미만 차단 — 법정대리인 동의 플로우는 이번 버전 미제공.
  Widget _buildBlocked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 72),
        const Icon(Icons.lock_outline_rounded, color: AppColors.textSecondary, size: 48),
        const SizedBox(height: 24),
        const Text(
          '만 14세 미만은\n이용할 수 없어요',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.3,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '관련 법령에 따라 만 14세 미만은 현재 서비스를 이용할 수 없습니다. 법정대리인 동의 절차는 추후 제공될 예정입니다.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5),
        ),
        const Spacer(),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _onBlockedLogout,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surfaceCard,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('로그아웃',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() {
            _ageOver14 = null;
            OnboardingDraft.instance.ageOver14 = null;
          }),
          child: const Text('다시 선택',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildNicknameForm() {
    final canSubmit = _available == true && !_submitting && _ageOver14 == true && _agreedTos && _agreedPrivacy;
    return Column(
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
                  fillColor: AppColors.surfaceElevated,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
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
              // 전체 동의 마스터 — 3개 일괄 체크. 개별 해제 가능, 스캔이미지는 선택 유지.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _setAllConsents(!_allAgreed),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: _allAgreed,
                        onChanged: (v) => _setAllConsents(v ?? false),
                        activeColor: AppColors.blue,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('전체 동의',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const Divider(color: AppColors.divider, height: 18),
              // 회원가입 필수 동의 (한국 개인정보보호법 + Apple App Review). 모두 체크돼야 "시작하기" 활성.
              // B2-21: 만14세 게이트를 별도 화면 대신 여기 필수 체크로 통합 (확인 여부만 기록, 생년월일 미저장).
              _ConsentCheckbox(
                checked: _ageOver14 == true,
                onChanged: (v) => setState(() {
                  _ageOver14 = v ? true : null;
                  OnboardingDraft.instance.ageOver14 = _ageOver14;
                }),
                label: '만 14세 이상입니다 (필수)',
              ),
              const SizedBox(height: 8),
              _ConsentCheckbox(
                checked: _agreedTos,
                onChanged: (v) => setState(() {
                  _agreedTos = v;
                  OnboardingDraft.instance.agreedTos = v;
                }),
                label: '이용약관에 동의합니다 (필수)',
                onLinkTap: () => context.push('/legal/terms'),
              ),
              const SizedBox(height: 8),
              _ConsentCheckbox(
                checked: _agreedPrivacy,
                onChanged: (v) => setState(() {
                  _agreedPrivacy = v;
                  OnboardingDraft.instance.agreedPrivacy = v;
                }),
                label: '개인정보처리방침에 동의합니다 (필수)',
                onLinkTap: () => context.push('/legal/privacy'),
              ),
              const SizedBox(height: 8),
              _ConsentCheckbox(
                checked: _agreedScanImages,
                onChanged: (v) => setState(() {
                  _agreedScanImages = v;
                  OnboardingDraft.instance.agreedScanImages = v;
                }),
                label: '스캔한 카드 이미지의 수집·활용에 동의합니다 (선택)',
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    );
  }
}

/// 가입 동의 체크박스 row — 라벨 + "보기" 링크. 필수 동의(_agreedTos/_agreedPrivacy)에만 사용.
class _ConsentCheckbox extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;
  final String label;
  final VoidCallback? onLinkTap; // null이면 '보기' 링크 숨김 (만14세 등 링크 없는 항목)

  const _ConsentCheckbox({
    required this.checked,
    required this.onChanged,
    required this.label,
    this.onLinkTap,
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
        if (onLinkTap != null)
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
