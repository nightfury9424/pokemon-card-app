import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_error_toast.dart';
import '../../core/widgets/app_success_toast.dart';
import '../../core/widgets/auth_image.dart';

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
  String? _profileImageUrl; // B2-10: 프로필 사진 (쿨다운 없음)
  bool _uploadingImage = false;

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

  /// B2-10: 갤러리에서 프로필 사진 선택 → 업로드(POST /me/profile-image) → 즉시 반영. 쿨다운 없음.
  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;
    try {
      // maxWidth 1024 + q85 로 image_picker 가 다운스케일+재인코딩(HEIC→JPEG) → 보통 수백 KB.
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery, maxWidth: 1024, imageQuality: 85);
      if (picked == null) return;
      if (!mounted) return;
      // B3-12: 압축 후에도 5MB 초과면(희박) 클라에서 먼저 차단 — 백엔드 5MB 한도와 일관.
      final bytes = await File(picked.path).length();
      if (bytes > 5 * 1024 * 1024) {
        if (!mounted) return;
        AppErrorToast.show(context, '이미지는 5MB 이하만 가능해요. 다른 사진을 선택해주세요.');
        return;
      }
      setState(() => _uploadingImage = true);
      final res = await ApiClient.postMultipart(
        '/api/users/me/profile-image',
        files: {'file': File(picked.path)},
      );
      final url = ((res['data'] as Map?)?['profileImageUrl'] as String?) ?? '';
      if (!mounted) return;
      setState(() {
        _profileImageUrl = url.isEmpty ? null : url;
        _uploadingImage = false;
      });
      AppSuccessToast.show(context, '프로필 사진이 변경됐어요');
    } on DioException catch (e) {
      // B3-11: "무조건 안돼" 제거 — 백엔드 사유(이미지 형식/5MB/정지 등)를 그대로 노출.
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      final body = e.response?.data;
      final reason = (body is Map && body['message'] is String &&
              (body['message'] as String).trim().isNotEmpty)
          ? body['message'] as String
          : (e.response?.statusCode == 413
              ? '이미지는 5MB 이하만 가능해요.'
              : '사진 변경에 실패했어요. 다시 시도해주세요.');
      AppErrorToast.show(context, reason);
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploadingImage = false);
      AppErrorToast.show(context, '사진 변경에 실패했어요. 다시 시도해주세요.');
    }
  }

  Future<void> _loadMe() async {
    try {
      final res = await ApiClient.get('/api/users/me');
      final data = (res['data'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        _currentNickname = (data['nickname'] as String?) ?? '';
        _cooldownDaysLeft = (data['nicknameCooldownDaysLeft'] as num?)?.toInt() ?? 0;
        final p = (data['profileImageUrl'] as String?) ?? '';
        _profileImageUrl = p.isEmpty ? null : p;
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
      final res = await ApiClient.put('/api/users/nickname', {'nickname': nickname});
      if (!mounted) return;
      // 거부(중복/쿨다운 등)는 HTTP 200 바디(status=fail)로 옴 → 성공 오인 방지.
      if (res['status'] != 'success') {
        setState(() {
          _submitting = false;
          _validationError = (res['message'] is String &&
                  (res['message'] as String).trim().isNotEmpty)
              ? res['message'] as String
              : '닉네임을 변경할 수 없어요.';
        });
        return;
      }
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

  /// 백엔드 envelope의 specific 사유 노출. NicknameValidator의 "닉네임은 2~15자여야 합니다"/
  /// "사용할 수 없는 닉네임입니다" 등을 사용자에게 그대로 노출. DioException 정공법 + toString fallback.
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
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('프로필 편집')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.blue)),
      );
    }

    final cooldownActive = _cooldownDaysLeft > 0;
    final canSubmit = !cooldownActive && _available == true && !_submitting;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('프로필 편집')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // B2-10: 프로필 사진 (쿨다운 없음). 탭하면 갤러리에서 변경.
              Center(
                child: GestureDetector(
                  onTap: _uploadingImage ? null : _pickAndUploadImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceCard,
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: _profileImageUrl != null
                            ? AuthImage(
                                url: _profileImageUrl!,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover)
                            : const Icon(Icons.person,
                                color: AppColors.textMuted, size: 48),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                              shape: BoxShape.circle, color: AppColors.blue),
                          child: _uploadingImage
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.camera_alt,
                                  color: Colors.white, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text('탭하여 프로필 사진 변경',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
              const SizedBox(height: 24),
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
