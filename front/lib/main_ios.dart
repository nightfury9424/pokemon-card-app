import 'app/app_bootstrap.dart';
import 'app/platform_app_config.dart';

/// iOS(App Store) 진입점.
///
/// 빌드: `flutter build ipa -t lib/main_ios.dart …` (scripts/build_prod.sh ipa 가 자동 지정)
/// 부팅 로직은 전부 [bootstrapApp] 공유 — 여기서는 iOS 셸 설정만 주입한다.
Future<void> main() => bootstrapApp(AppConfig.ios);
