/// 베타 release feature toggle.
///
/// 베타 1.0 = AI 그레이딩 비활성 (출시 후 데이터 축적 → AI 모델링 cycle → 재도입).
/// 코드 / endpoint / DB 보존. 진입 entry 만 차단.
///
/// Plan D (Hotfix 10-2): AI 점수/등급/result 화면은 차단하되,
/// 앞/뒷면 실사진 등록 인프라 (capture screen + /precheck + AssetImage FRONT/BACK)
/// 는 `mode='sell_photo'` 분기로 재사용 — "판매 사진 등록" 용도.
/// 신규 endpoint `POST /api/assets/{assetId}/sell-photos` 가 sell flow 전용.
class FeatureFlags {
  /// AI 그레이딩 (점수/등급 산정) = 베타 1.0 false.
  /// 사유: 큰 손상 (접힘/주름/눌림) detect 실패. 잘못된 점수 → 거래 신뢰 위협.
  /// 재도입 trigger: 베타 사용자 사진 + 자기 라벨 데이터 축적 후 ML 학습 (별도 cycle).
  /// false 여도 capture screen 은 `mode='sell_photo'` 로 진입 가능 (Plan D).
  static const bool enableAiGrading = false;
}
