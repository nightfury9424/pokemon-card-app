import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front/app/platform_app_config.dart';
import 'package:front/features/auth/login_screen.dart';
import 'package:front/features/auth/phone_verify_sheet.dart';

/// 플랫폼 셸 분리(2026-07-20) 검증.
/// - AppConfig: 플랫폼별 노출 계약 (iOS Apple 로그인 O / Android X · 오리파 양쪽 X)
/// - 로그인 화면: Apple 버튼이 config 하나로만 통제되는지 (공백도 안 남는지)
/// - 전화 인증: 서버 authoritative E.164 → 한국 표시 형식
void main() {
  tearDown(AppConfig.resetForTest);

  group('AppConfig 플랫폼 계약', () {
    test('iOS 셸 — Apple 로그인 노출(심사 요건) · 오리파 미출시', () {
      expect(AppConfig.ios.showAppleSignIn, isTrue);
      expect(AppConfig.ios.enableOripa, isFalse);
      expect(AppConfig.ios.platformId, 'ios');
    });

    test('Android 셸 — Apple 로그인 미노출(오너 결정) · 오리파 미출시', () {
      expect(AppConfig.android.showAppleSignIn, isFalse);
      expect(AppConfig.android.enableOripa, isFalse);
      expect(AppConfig.android.platformId, 'android');
    });

    test('fallback(진입점 미경유) — 미출시 기능 전부 off · 기존 화면 기본 동작 보존', () {
      expect(AppConfig.fallback.enableOripa, isFalse);
      expect(AppConfig.fallback.showAppleSignIn, isTrue);
    });

    test('install 이 current 를 바꾸고 resetForTest 가 fallback 으로 복원', () {
      AppConfig.install(AppConfig.android);
      expect(AppConfig.current.isAndroid, isTrue);
      AppConfig.resetForTest();
      expect(AppConfig.current.platform, AppPlatform.unknown);
    });
  });

  group('로그인 화면 — Apple 버튼 플랫폼 분기', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pump(); // Image.network 오류 프레임 소화(errorBuilder 폴백)
    }

    testWidgets('iOS 셸: Apple로 시작하기 표시', (tester) async {
      AppConfig.install(AppConfig.ios);
      await pump(tester);
      expect(find.text('Apple로 시작하기'), findsOneWidget);
      expect(find.text('Google로 시작하기'), findsOneWidget);
    });

    testWidgets('Android 셸: Apple로 시작하기 미표시 · Google 만', (tester) async {
      AppConfig.install(AppConfig.android);
      await pump(tester);
      expect(find.text('Apple로 시작하기'), findsNothing);
      expect(find.text('Google로 시작하기'), findsOneWidget);
    });
  });

  group('전화 인증 — 서버 E.164 표시 형식', () {
    test('+82 11자리 → 010-1234-5678', () {
      expect(formatKrPhoneForDisplay('+821012345678'), '010-1234-5678');
    });
    test('+82 10자리(구형) → 011-123-4567', () {
      expect(formatKrPhoneForDisplay('+82111234567'), '011-123-4567');
    });
    test('이미 0 시작 로컬 입력도 동일 형식', () {
      expect(formatKrPhoneForDisplay('01012345678'), '010-1234-5678');
    });
  });
}
