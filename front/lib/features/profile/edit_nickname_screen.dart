import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_success_toast.dart';

class EditNicknameScreen extends StatefulWidget {
  const EditNicknameScreen({super.key});

  @override
  State<EditNicknameScreen> createState() => _EditNicknameScreenState();
}

class _EditNicknameScreenState extends State<EditNicknameScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _checking = false;
  bool? _available;
  String? _validationError;
  bool _submitting = false;
  int _requestToken = 0;

  String _currentNickname = '';
  int _cooldownDaysLeft = 0;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMe() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      final data = (res['data'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        _currentNickname = (data['nickname'] as String?) ?? '';
        _cooldownDaysLeft = (data['nicknameCooldownDaysLeft'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _onChanged(String value) {
    setState(() {
      _available = null;
      _validationError = null;
    });
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == _currentNickname.toLowerCase()) return;
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
      await ApiClient.put('/api/users/nickname', {'nickname': nickname});
      if (!mounted) return;
      AppSuccessToast.show(context, '닉네임이 변경되었습니다');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _validationError = _extractMessage(e);
        _available = false;
      });
    }
  }

  String _extractMessage(Object e) {
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
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('닉네임 변경')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.blue)),
      );
    }

    final cooldownActive = _cooldownDaysLeft > 0;
    final canSubmit = !cooldownActive && _available == true && !_submitting;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('닉네임 변경')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Text('현재 닉네임',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    const Spacer(),
                    Text(
                      _currentNickname,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (cooldownActive) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined, color: AppColors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '닉네임 변경은 $_cooldownDaysLeft일 후 가능합니다',
                          style: const TextStyle(
                            color: AppColors.red,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                enabled: !cooldownActive,
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
                  hintText: '새 닉네임 (2~15자)',
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
              const SizedBox(height: 8),
              const Text(
                '닉네임 변경 후 30일이 지나야 다시 변경할 수 있습니다.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
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
                          '변경',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
