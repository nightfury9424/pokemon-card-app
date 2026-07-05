import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_colors.dart';

/// 휴대폰 OTP 인증 시트 (Firebase Phone Auth). 거래·채팅 신뢰 배지·게이트용.
///
/// 흐름: 번호(+82) 입력 → verifyPhoneNumber(SMS) → 코드 입력 → signInWithCredential →
///       Firebase ID 토큰 → 백엔드 /api/users/phone/verify 검증·저장 → Firebase signOut.
/// (우리 앱 메인 인증은 커스텀 JWT라 Firebase 세션은 검증 후 버림.)
/// 한국 번호(+82)만 허용. 재전송 60초 쿨타임. 일일/실패 제한은 Firebase 서버 측 quota.
/// 반환: 인증 성공 시 true.
class PhoneVerifySheet {
  PhoneVerifySheet._();

  /// 거래 시작 게이트 — 미인증이면 인증 시트를 띄우고, 인증 완료/성공 시 true.
  /// 판매하기/구매하기 등 거래 진입 시점에서 호출. true 면 진행, false 면 중단.
  static Future<bool> ensureVerified(BuildContext context) async {
    try {
      final me = await ApiClient.get('/api/users/me');
      if (me['data'] is Map && me['data']['phoneVerified'] == true) return true;
    } catch (_) {
      // /me 실패 시 게이트로 막지 않음(거래 자체 백엔드가 backstop) — 인증 시트 시도.
    }
    if (!context.mounted) return false;
    return show(context);
  }

  static Future<bool> show(BuildContext context) async {
    final res = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      // 인증 도중 실수로 슬라이드/바깥탭 닫힘 방지 — 진행 상태 유실 차단.
      // 의도적 취소는 시트 상단 X 버튼으로만.
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const _PhoneVerifyBody(),
      ),
    );
    return res == true;
  }
}

class _PhoneVerifyBody extends StatefulWidget {
  const _PhoneVerifyBody();

  @override
  State<_PhoneVerifyBody> createState() => _PhoneVerifyBodyState();
}

class _PhoneVerifyBodyState extends State<_PhoneVerifyBody> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String? _verificationId;
  bool _otpStep = false;
  bool _busy = false;
  bool _sendingOtp = false; // 낙관적 전환: OTP 화면 진입했으나 아직 SMS 발송 대기 중
  String? _error;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    // APNs 토큰 프리워밍 — 사용자가 번호 입력하는 동안 토큰을 미리 준비해
    // verifyPhoneNumber 시점의 앱검증 지연을 줄인다(베스트 에포트, 실패 무시).
    FirebaseMessaging.instance.getAPNSToken().catchError((_) => null);
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  /// 한국 번호만 → +82 E.164 (앞 0 제거).
  String _toE164(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('82')) return '+$d';
    if (d.startsWith('0')) return '+82${d.substring(1)}';
    return '+82$d';
  }

  /// 한국 휴대폰 형식 검증 (010/011/016/017/018/019 + 7~8자리).
  bool _validKr(String raw) {
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return RegExp(r'^01[016789]\d{7,8}$').hasMatch(d);
  }

  Future<void> _sendCode() async {
    if (!_validKr(_phone.text)) {
      setState(() => _error = '올바른 휴대폰 번호를 입력해주세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // 우리 측 strict 가드 — 휴대폰/IP/계정별 횟수·쿨타임. 통과해야 Firebase 발송.
      final gate = await ApiClient.post(
          '/api/users/phone/request-otp', {'phone': _phone.text});
      if (gate['status'] != 'success') {
        if (mounted) setState(() {
              _busy = false;
              _error = (gate['message'] as String?) ?? '요청이 제한됐어요. 잠시 후 다시 시도해주세요';
            });
        return;
      }
      // 낙관적 전환 — 게이트 통과 즉시 OTP 화면으로 전환(입력 대기 표시).
      // Firebase 앱검증/발송 지연(2~5s)을 화면 전환 뒤로 숨겨 체감 대기를 없앤다.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _otpStep = true;
        _sendingOtp = true;
        _error = null;
      });
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _toE164(_phone.text),
        timeout: const Duration(seconds: 60),
        verificationCompleted: (cred) async => _completeWith(cred), // iOS 자동 인증
        verificationFailed: (e) {
          if (mounted) setState(() {
                _otpStep = false; // 폰 입력 단계로 되돌림
                _sendingOtp = false;
                _busy = false;
                _error = _mapErr(e);
              });
        },
        codeSent: (vid, _) {
          if (!mounted) return;
          setState(() {
            _sendingOtp = false; // 발송 완료 → 입력 활성화
            _verificationId = vid;
          });
          _startResendCooldown();
        },
        codeAutoRetrievalTimeout: (vid) => _verificationId = vid,
      );
    } catch (e) {
      if (mounted) setState(() {
            _otpStep = false;
            _sendingOtp = false;
            _busy = false;
            _error = '요청실패: $e';
          });
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendIn = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendIn <= 1) {
        t.cancel();
        setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  Future<void> _submitOtp() async {
    final code = _otp.text.trim();
    if (_verificationId == null) {
      setState(() => _error = '먼저 인증번호를 받아주세요');
      return;
    }
    if (code.length < 6) {
      setState(() => _error = '인증번호 6자리를 입력해주세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _completeWith(PhoneAuthProvider.credential(
        verificationId: _verificationId!, smsCode: code));
  }

  Future<void> _completeWith(PhoneAuthCredential cred) async {
    try {
      final uc = await FirebaseAuth.instance.signInWithCredential(cred);
      final idToken = await uc.user?.getIdToken();
      if (idToken == null) throw Exception('no-id-token');
      final res = await ApiClient.post(
          '/api/users/phone/verify', {'firebaseIdToken': idToken});
      await FirebaseAuth.instance.signOut(); // Firebase 세션 버림 (우리 인증은 JWT)
      final ok = res['status'] == 'success' ||
          (res['data'] is Map && (res['data']['phoneVerified'] == true));
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = (res['message'] as String?) ?? '인증에 실패했어요';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() {
            _busy = false;
            _error = _mapErr(e);
          });
    } catch (e) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (mounted) setState(() {
            _busy = false;
            _error = '인증 처리에 실패했어요. 다시 시도해주세요';
          });
    }
  }

  String _mapErr(FirebaseAuthException e) => switch (e.code) {
        'invalid-phone-number' => '올바른 휴대폰 번호를 입력해주세요',
        'invalid-verification-code' => '인증번호가 올바르지 않아요',
        'session-expired' => '인증 시간이 만료됐어요. 다시 받아주세요',
        'too-many-requests' || 'quota-exceeded' => '요청이 많아요. 잠시 후 다시 시도해주세요',
        // 진단: 알 수 없는 코드는 화면에 그대로 노출 (iOS 라이브 로그 미동작 → 원인 파악용)
        _ => '오류[${e.code}] ${e.message ?? ''}',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close,
                        color: AppColors.textMuted, size: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text('휴대폰 인증',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4)),
          const SizedBox(height: 6),
          Text(
            _otpStep
                ? (_sendingOtp
                    ? '인증번호를 보내고 있어요…'
                    : '문자로 받은 인증번호 6자리를 입력해주세요')
                : '거래·채팅 신뢰를 위해 휴대폰 번호를 인증해요',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 22),
          if (!_otpStep) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                LengthLimitingTextInputFormatter(13),
              ],
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
              decoration: _dec('010-1234-5678', prefix: '🇰🇷 +82  '),
            ),
          ] else ...[
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6),
              textAlign: TextAlign.center,
              onChanged: (v) {
                if (v.length == 6 && !_busy && !_sendingOtp) _submitOtp();
              },
              decoration: _dec('______'),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed:
                    (_resendIn > 0 || _busy || _sendingOtp) ? null : _sendCode,
                child: Text(
                  _resendIn > 0 ? '재전송 ($_resendIn초)' : '인증번호 재전송',
                  style: TextStyle(
                      color: _resendIn > 0
                          ? AppColors.textMuted
                          : AppColors.blueLight,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_busy || _sendingOtp)
                  ? null
                  : (_otpStep ? _submitOtp : _sendCode),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceCard,
                disabledForegroundColor: AppColors.textMuted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: (_busy || _sendingOtp)
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(_otpStep ? '인증 완료' : '인증번호 받기',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixText: prefix,
        prefixStyle:
            const TextStyle(color: AppColors.textSecondary, fontSize: 15),
        filled: true,
        fillColor: AppColors.surfaceElevated,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
      );
}
