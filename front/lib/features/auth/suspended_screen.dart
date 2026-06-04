import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_state.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_info_toast.dart';
import '../../core/widgets/app_success_toast.dart';

/// 정지(suspended) 계정 전체 가림 게이트.
/// - 진입: ApiClient 가 403 USER_SUSPENDED 감지 → AuthState.markSuspended → 라우터가 여기로.
/// - 사유: /api/users/me(정지자도 통과)의 suspensionReason.
/// - 이의신청: POST /api/suspension-appeals (정지자 전용 allowlist). 그 외 API 는 전부 403.
/// - 로그아웃 가능. 복구된 계정이면(/me suspended=false) 게이트 자동 해제.
class SuspendedScreen extends StatefulWidget {
  const SuspendedScreen({super.key});

  @override
  State<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends State<SuspendedScreen> {
  final _appealCtrl = TextEditingController();
  String? _reason;
  bool _loading = true;
  bool _submitting = false;
  bool _appealSent = false;

  @override
  void initState() {
    super.initState();
    _loadReason();
  }

  @override
  void dispose() {
    _appealCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReason() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      if (!mounted) return;
      final data = res['data'] as Map<String, dynamic>?;
      // 복구된 계정만 게이트 해제 — suspended 키 누락(파싱 오류 등)으로 잘못 해제되지 않게 엄격 비교(== false).
      if (data != null && data['suspended'] == false) {
        AuthState.instance.clearSuspended();
        return;
      }
      setState(() {
        _reason = (data?['suspensionReason'] as String?)?.trim();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitAppeal() async {
    final text = _appealCtrl.text.trim();
    if (text.isEmpty) {
      AppInfoToast.show(context, '이의신청 내용을 입력해주세요.');
      return;
    }
    setState(() => _submitting = true);
    try {
      final res = await ApiClient.post('/api/suspension-appeals', {'content': text});
      if (!mounted) return;
      if (res['status'] != 'success') {
        AppErrorToast.show(
          context,
          (res['message'] is String && (res['message'] as String).trim().isNotEmpty)
              ? res['message'] as String
              : '이의신청 접수에 실패했어요.',
        );
        return;
      }
      setState(() => _appealSent = true);
      AppSuccessToast.show(context, '이의신청이 접수되었어요. 검토 후 안내드릴게요.');
    } catch (_) {
      if (mounted) AppErrorToast.show(context, '이의신청 접수에 실패했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _quitApp() {
    // 앱 종료 — iOS는 Apple 정책상 강제 종료 대신 백그라운드로 보냄(SystemNavigator.pop).
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 뒤로가기로 게이트 탈출 차단.
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.gavel_rounded, color: AppColors.red, size: 48),
                  const SizedBox(height: 18),
                  const Text(
                    '이용이 정지되었습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '운영정책 위반으로 계정 이용이 제한되었어요.\n사유를 확인하고, 이의가 있으면 아래로 신청해주세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  // 정지 사유 박스
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.red.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('정지 사유',
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          _loading
                              ? '불러오는 중…'
                              : (_reason != null && _reason!.isNotEmpty
                                  ? _reason!
                                  : '관리자에게 문의해주세요.'),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  // 이의신청
                  if (_appealSent)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '이의신청이 접수되었어요. 검토 후 안내드릴게요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    )
                  else ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('이의신청 / 문의하기',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _appealCtrl,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 1000,
                      enabled: !_submitting,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: '정지 사유에 대한 의견이나 문의 내용을 적어주세요.',
                        hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppColors.surfaceCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _submitAppeal,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('이의신청 보내기'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextButton(
                    onPressed: _quitApp,
                    child: const Text('앱 종료하기',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
