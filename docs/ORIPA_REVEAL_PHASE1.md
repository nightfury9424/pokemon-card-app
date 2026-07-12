# 오리파 리빌 Phase 1 — 승인된 구조 v4 (구현 스펙)

> 저장소 진실원. 스토리보드 **v4 승인·잠금 (2026-07-13)**. 시안: `~/Desktop/oripa_storyboard_v4.html`.
> 이전 v1(실버 보안봉투 + 팩 아래로 내려 번호판) 및 v2(옆면 카드 옆 문구)는 **폐기**.

## 승인된 리빌 흐름

**NORMAL** (`intensity == normal`):
```
닫힌 팩 → 상단 절취(탭 옆으로) → 카드 뒷면 상승(후광 없음, 팩 잔해 없음)
→ 사용자 탭 → 일반 플립(~320~420ms) → 바로 앞면 공개
```
암전·문구·"꽝" 없음. 최소 조명만.

**HIT** (`intensity == rare/hit/jackpot`):
```
닫힌 팩 → 상단 절취 → 카드 뒷면 상승 + [금빛 후광]
→ 사용자 탭 → 전체 화면 암전(카드·팩 화면에서 퇴장)
→ 검은 무대에서 문구 1개씩 (이전 사라지고 다음):
   RAW: 세트 → RAW → 레어도 → 이름
   GRADED: 세트 → 회사 → 등급숫자 → 레어도 → 이름
→ 짧은 정적 → 중심광 → 빛 폭발 → 밝아지며 실제 카드/슬랩 앞면 HERO 첫 등장(후광 뒤에 정착)
```

## 아우라 = 기존 `RevealDescriptor.intensity` 재사용 (새 필드 없음)
`RevealPolicy.intensityFor()` 발급(서버권위형, 클라 교환P 자동계산 금지). 매핑:
- `normal` → 후광 없음 (NORMAL 경로)
- `rare` → 얇은 금빛 후광 + 약한 입자
- `hit` → 넓은 광륜 + 보케 다수
- `jackpot` → 폭발형 후광 + 광선 + 강한 발광
비주얼: 세븐나이츠식 **카드 뒤 금빛 후광 + 소프트 번짐 + 골드 보케 입자 + 테두리 발광**. 얇은 링/네온 금지. 차등=광량·범위·입자(색 아님).

## 구현 중 1차 조정 4가지
1. HIT 아우라 = 외곽선 강조 아니라 **카드 뒤 공간 전체 금빛 후광 중심**(중심광+주변 번짐+소량 입자).
2. HERO 카드 **존재감 크게** — 보상카드 먼저, 버튼 시선 덜.
3. NORMAL 앞면 **담백** — 후광/광폭발 금지, 최소 조명.
4. HIT 타이밍 **절대 겹침 금지**: 탭→암전→카드/팩 퇴장→문구 1개씩→정적→중심광→폭발→HERO.

## 불변 계약 (건드리지 마)
- `reveal_view.dart` RevealView 상태머신 / `drawId` / recovery(committed/revealed) 계약.
- `markRevealStarted` = 사용자 플립 시작 순간. `markRevealed` = 앞면 HERO 완전 노출 후.
- HIT 여부·intensity = `RevealDescriptor`(정책 발급). 클라가 가격/레어도로 계산 금지, 운영 down/off 가능.
- 플립 전까지 팩·카드뒷면·상승은 NORMAL/HIT 동일, **후광만 차이**. 앞면은 (HIT는)문구 끝난 뒤 첫 노출.

## 파일
`front/lib/features/oripa/draw/oripa_draw_screen.dart` (스테이지·절취·상승·플립), `draw/reveal_view.dart` (상태머신·문구·HERO), `data/reveal_models.dart` (RevealDescriptor/intensity/RevealConfig), `oripa_common.dart`, `data/oripa_prizes.dart`.

## 승인 기준 (통과해야 Phase 1 완료)
- [ ] 상단 절취 개봉(팩 중앙 고정), 카드 뒷면 상승, **팩 잔해 안 남김**
- [ ] 뒷면 후광 유무로 NORMAL/HIT 구분(뒤집기 전)
- [ ] NORMAL: 후광·암전·문구·"꽝" 없이 담백 플립
- [ ] HIT: 암전 → 문구 **1개씩**(누적 금지) → 정적 → 빛폭발 → 앞면 HERO
- [ ] 05~10 타이밍 겹침 없음
- [ ] HERO 카드 존재감(RAW BoxFit.contain / GRADED 슬랩 화면 58~68%)
- [ ] 상태머신·drawId·recovery·markReveal* 계약 유지, flutter analyze 클린
- [ ] 기준선 IPA 실기기 전/후 영상 비교

## 절차: v4 잠금 → Flutter 구현 → analyze/test → 기준선 IPA → 실기기 4개 조정.
