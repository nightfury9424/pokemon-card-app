import 'app/app_bootstrap.dart';
import 'app/platform_app_config.dart';

/// Android(Play Store) 진입점.
///
/// 빌드: `flutter build appbundle -t lib/main_android.dart …` (scripts/build_prod.sh 가 자동 지정)
/// 부팅 로직은 전부 [bootstrapApp] 공유 — 여기서는 Android 셸 설정만 주입한다.
Future<void> main() => bootstrapApp(AppConfig.android);
