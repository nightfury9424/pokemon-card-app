import 'dart:io' show Platform;

import 'app/app_bootstrap.dart';
import 'app/platform_app_config.dart';

// 플랫폼 분리(2026-07-20) 후에도 기존 도구가 깨지지 않도록 유지하는 **폴백 진입점**:
//  - `flutter run` (-t 미지정) · IDE 기본 실행 · 기존 스크립트
//  - 릴리즈 빌드는 반드시 명시 진입점 사용: iOS=main_ios.dart / Android=main_android.dart
//    (scripts/build_prod.sh 가 타깃별로 자동 지정)
// 앱 본문·부팅 로직은 전부 app/app_bootstrap.dart 공유 — 여기는 config 선택만 한다.
export 'app/app_bootstrap.dart' show PokemonCardApp, rootScaffoldMessengerKey;

Future<void> main() =>
    bootstrapApp(Platform.isIOS ? AppConfig.ios : AppConfig.android);
