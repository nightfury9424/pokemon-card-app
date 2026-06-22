/// 공통 레이아웃 디자인 상수 (단일 진실원).
/// 기기 모델명으로 분기하지 않는다 — 값은 디자인에서 도출되고, 적응형 판단은
/// 각 위젯이 LayoutBuilder/Wrap/textScaler 로 실제 가용폭 기준으로 한다.
class AppDimens {
  AppDimens._();

  /// 셸 중앙 스캔 FAB 직경. main_shell `_PressableFab` 가 이 값을 사용.
  static const double scanFabDiameter = 56.0;

  /// FAB 아래 콘텐츠가 가리지 않도록 둘 추가 여백.
  static const double scanFabContentClearance = 20.0;

  /// centerDocked 스캔 FAB 가 본문으로 돌출하는 양(직경/2) + 여백.
  /// 셸 바텀바 높이·홈 인디케이터(Safe Area)는 main_shell `_BottomNav` 의
  /// SafeArea 가 이미 처리하므로 여기서 viewPadding 을 더하지 않는다(이중 inset 방지).
  /// → 기기 무관 상수. 본문 스크롤뷰가 이 값을 bottom padding 으로 사용.
  static const double bottomContentInsetForScanFab =
      scanFabDiameter / 2 + scanFabContentClearance;
}
