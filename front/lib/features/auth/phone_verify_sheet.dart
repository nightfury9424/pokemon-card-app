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

/// 서버가 검증한 E.164(+8210…) → 한국 표시 형식(010-1234-5678).
/// (top-level: 위젯 밖에서도 테스트 가능해야 해서 — 자동 인증 완료 표시의 번호 형식이 여기서 결정된다)
String formatKrPhoneForDisplay(String e164) {
  var d = e164.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('82')) d = '0${d.substring(2)}';
  if (d.length == 11) return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}';
  if (d.length == 10) return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}';
  return d;
}

class _PhoneVerifyBodyState extends State<_PhoneVerifyBody> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  String? _verificationId;
  bool _otpStep = false;
  bool _busy = false; // 수동 확인 → 서버 검증 중 (serverVerifying)
  bool _sendingOtp = false; // 낙관적 전환: OTP 화면 진입했으나 아직 SMS 발송 대기 중
  // Android SMS 자동 확인(auto-retrieval/instant verification) 진행 중 — OTP 칸 대신 상태 표시.
  bool _autoVerifying = false;
  // 서버 /phone/verify 까지 성공 — **이때만** 완료 UI. Firebase credential 성공만으론 올리지 않는다.
  bool _verified = false;
  String? _verifiedPhone; // 서버가 검증한 authoritative 번호(E.164 → 표시 형식 변환)
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
        // Android SMS auto-retrieval / instant verification — Google Play 서비스가 이 기기에
        // 도착한 문자를 자동 확인해 credential 을 만들어준다(iOS 아님 — 과거 주석이 반대였음).
        // 자동 인증은 정상 흐름이므로 막지 않는다. 대신 사용자가 과정을 볼 수 있게
        // autoVerifying 상태를 표시하고, 서버 검증까지 끝나야 완료 UI 로 간다.
        verificationCompleted: (cred) async {
          if (!mounted || _verified || _busy || _autoVerifying) return;
          setState(() {
            _autoVerifying = true;
            _sendingOtp = false;
            _error = null;
          });
          await _completeWith(cred);
        },
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
        // 완료의 진실원 = 서버 /phone/verify 성공. 서버가 돌려준 phoneE164 가 authoritative —
        // 입력값이 아니라 이 값을 표시한다(자동 인증이면 사용자가 입력한 적도 없다).
        final e164 = (res['data'] is Map) ? res['data']['phoneE164'] as String? : null;
        setState(() {
          _verified = true;
          _busy = false;
          _autoVerifying = false;
          _verifiedPhone = formatKrPhoneForDisplay(e164 ?? _phone.text);
          _error = null;
        });
        // 완료 상태(번호 + 인증 완료 스위치 ON)를 잠깐 보여준 뒤 닫는다 —
        // 이전엔 즉시 pop 이라 자동 인증 시 아무 피드백 없이 시트가 사라졌다(오너 지적).
        await Future.delayed(const Duration(milliseconds: 1000));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _busy = false;
          _autoVerifying = false; // 자동 인증이었어도 수동 OTP 입력으로 fallback
          _error = (res['message'] as String?) ?? '인증에 실패했어요';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() {
            _busy = false;
            _autoVerifying = false;
            _error = _mapErr(e);
          });
    } catch (e) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (mounted) setState(() {
            _busy = false;
            _autoVerifying = false;
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
                  // 자동/서버 검증 진행 중·완료 표시 중엔 닫기 비활성 — 중복 조작·상태 유실 방지.
                  onTap: (_autoVerifying || _busy || _verified)
                      ? null
                      : () => Navigator.of(context).pop(false),
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
            _verified
                ? '전화번호 인증이 완료됐어요'
                : _autoVerifying
                    ? '문자를 자동으로 확인하고 있습니다…'
                    : _otpStep
                        ? (_sendingOtp
                            ? '인증번호를 보내고 있어요…'
                            : '문자로 받은 인증번호 6자리를 입력해주세요')
                        : '거래·채팅 신뢰를 위해 휴대폰 번호를 인증해요',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 22),
          if (_verified) ...[
            // ── 인증 완료: 서버가 검증한 번호(읽기 전용) + read-only 상태 스위치 ON ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _verifiedPhone ?? '',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const _VerifiedSwitch(),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_rounded, color: AppColors.blue, size: 18),
                SizedBox(width: 6),
                Text('전화번호 인증 완료',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ] else if (_autoVerifying) ...[
            // ── Android 자동 확인 중: OTP 칸 대신 상태 표시 (가짜 코드 채움 금지) ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.blue)),
                  SizedBox(width: 12),
                  Text('문자를 자동으로 확인하고 있습니다…',
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ] else if (!_otpStep) ...[
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
          if (!_verified)
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: (_busy || _sendingOtp || _autoVerifying)
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
              child: (_busy || _sendingOtp || _autoVerifying)
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

/// 인증 상태 표시용 **read-only 스위치**. 사용자 조작 컨트롤이 아니다 —
/// 서버 검증 완료를 보여주는 indicator 이며, 탭해도 상태가 바뀌지 않는다.
/// 등장 시 OFF→ON 으로 밀리는 애니메이션으로 "방금 인증됐다"를 보여준다.
class _VerifiedSwitch extends StatefulWidget {
  const _VerifiedSwitch();

  @override
  State<_VerifiedSwitch> createState() => _VerifiedSwitchState();
}

class _VerifiedSwitchState extends State<_VerifiedSwitch> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    // 첫 프레임은 OFF 로 그린 뒤 ON 으로 — 전환 애니메이션이 보이게.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _on = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: _on ? AppColors.blue : AppColors.divider,
          borderRadius: BorderRadius.circular(14),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: _on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
                color: Colors.white, shape: BoxShape.circle),
            child: _on
                ? const Icon(Icons.check_rounded,
                    size: 16, color: AppColors.blue)
                : null,
          ),
        ),
      ),
    );
  }
}
