import 'dart:io' show Platform;

/// 앱이 실행 중인 스토어 트랙.
enum AppPlatform {
  ios,
  android,

  /// 진입점을 거치지 않은 실행(단위 테스트 등). **미출시 기능은 전부 off** 로 취급한다.
  unknown,
}

/// 플랫폼별 앱 셸 설정.
///
/// ## 이게 필요한 이유
/// iOS 와 Android 는 **스토어 심사 주기가 다르다.** Android 심사를 위해 기능을 잠그는 변경이
/// 이미 라이브인 iOS 동작을 바꾸면 안 되고, 반대도 마찬가지다. 그래서 코드베이스를 복제하는 대신
/// **앱 셸(진입점 + 설정)만** 플랫폼별로 나눈다. 도메인·API·UI·기능 코드는 전부 공유한다.
///
/// ## [FeatureFlags] 와의 경계
/// - `FeatureFlags` = **빌드 전역** 컴파일 상수(예: AI 그레이딩). 플랫폼과 무관.
/// - `AppConfig`    = **플랫폼별** 셸 설정. 같은 코드로 두 스토어에 다른 노출을 낼 때만 쓴다.
/// 둘을 섞지 말 것 — 전자는 tree-shaking 대상, 후자는 진입점이 주입한다.
class AppConfig {
  const AppConfig._({
    required this.platform,
    required this.enableOripa,
    required this.showAppleSignIn,
  });

  final AppPlatform platform;

  /// 오리파(입점형 실물 카드) — **미출시**. R4 목업 계약만 동결됐고 서버가 없다.
  /// 실제 API 가 붙고 스토어별로 열 준비가 되면 해당 플랫폼만 true 로 바꾼다.
  final bool enableOripa;

  /// 로그인 화면의 "Apple로 시작하기" 노출.
  /// iOS = true — 다른 소셜 로그인을 쓰면 Sign in with Apple 이 심사 요건(HIG 4.8).
  /// Android = false — Apple 계정 로그인이 어색한 데다 노출할 이유가 없음(오너 결정).
  /// Apple 인증 서비스·백엔드 로직은 삭제하지 않는다 — **렌더링만** 이 플래그로 통제.
  final bool showAppleSignIn;

  static const AppConfig ios = AppConfig._(
    platform: AppPlatform.ios,
    enableOripa: false,
    showAppleSignIn: true,
  );

  static const AppConfig android = AppConfig._(
    platform: AppPlatform.android,
    enableOripa: false,
    showAppleSignIn: false,
  );

  /// 진입점을 안 거친 경우의 안전 기본값 — 미출시 기능 전부 off.
  /// (단위 테스트가 위젯을 직접 띄우는 기존 방식이 그대로 동작하게 하기 위함)
  /// showAppleSignIn 은 iOS 와 동일한 true — 기존 화면·테스트의 기본 동작 보존.
  static const AppConfig fallback = AppConfig._(
    platform: AppPlatform.unknown,
    enableOripa: false,
    showAppleSignIn: true,
  );

  static AppConfig? _current;

  /// 진입점(main_ios / main_android)이 부팅 시 한 번 설치한다.
  static void install(AppConfig config) => _current = config;

  /// 테스트에서 플랫폼별 동작을 검증한 뒤 되돌리기 위한 용도.
  static void resetForTest() => _current = null;

  static AppConfig get current => _current ?? fallback;

  bool get isIOS => platform == AppPlatform.ios;
  bool get isAndroid => platform == AppPlatform.android;

  /// 서버에 보내는 플랫폼 식별자. 진입점이 설치되지 않았으면 런타임으로 폴백한다
  /// (기존 `Platform.isIOS ? 'ios' : 'android'` 동작 보존).
  String get platformId {
    switch (platform) {
      case AppPlatform.ios:
        return 'ios';
      case AppPlatform.android:
        return 'android';
      case AppPlatform.unknown:
        return Platform.isIOS ? 'ios' : 'android';
    }
  }
}
