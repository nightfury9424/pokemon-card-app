/// 베타 release feature toggle.
///
/// 베타 1.0 = AI 그레이딩 비활성 (출시 후 데이터 축적 → AI 모델링 cycle → 재도입).
/// 코드 / endpoint / DB 보존. 진입 entry 만 차단.
class FeatureFlags {
  /// AI 그레이딩 = 베타 1.0 false.
  /// 사유: 큰 손상 (접힘/주름/눌림) detect 실패. 잘못된 점수 → 거래 신뢰 위협.
  /// 재도입 trigger: 베타 사용자 사진 + 자기 라벨 (상태 4단계) 데이터 축적 후 ML 학습 (별도 1주 cycle).
  static const bool enableAiGrading = false;
}
