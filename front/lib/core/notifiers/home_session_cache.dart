/// 홈 데이터 세션 캐시 — 탭 전환으로 HomeScreen State 가 재생성돼도(ShellRoute 구조상
/// `MainShell.body = child` 라 탭 이동마다 child 위젯이 새로 만들어짐) 캐시가 있으면
/// 스플래시(PokeFolio 로고+스피너)/회색박스 없이 즉시 렌더 + 백그라운드 silent refresh.
///
/// - 유지 범위: **앱 프로세스 생존 동안만**(static). 앱 완전 종료 후 첫 실행은 캐시 없음 → 기존 첫 진입 로딩 허용.
/// - 로그아웃·계정 변경 시 반드시 [clear] — 이전 유저의 자산/포트폴리오가 다음 유저에게 노출되는 사고 방지.
///   (AuthService.logout 에서 호출. OnboardingDraft.clear 와 동일 패턴.)
class HomeSessionCache {
  HomeSessionCache._();

  /// 캐러셀 임계 데이터(topCards/hotCards)가 한 번이라도 채워졌는지 — seed 가능 여부 판정.
  static bool hasData = false;

  static String? userId;
  static List<Map<String, dynamic>> topCards = [];
  static List<Map<String, dynamic>> hotCards = [];
  static List<Map<String, dynamic>> topGainerCards = [];
  static List<Map<String, dynamic>> recentTrades = [];
  static List<Map<String, dynamic>> myAssets = [];
  static Map<String, dynamic>? portfolio;

  static void clear() {
    hasData = false;
    userId = null;
    topCards = [];
    hotCards = [];
    topGainerCards = [];
    recentTrades = [];
    myAssets = [];
    portfolio = null;
  }
}
