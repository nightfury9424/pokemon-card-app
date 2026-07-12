# 오리파 리빌 Phase 1 — 봉인 오브젝트 + 등장 모션 (구현계획·승인기준)

> 저장소 진실원. Claude 개인 메모리 아닌 이 문서 + 테스트가 기준.
> Phase 1 = "뽑고 싶게 보이는" 기준선. **Phase 1 승인 전 가챠 레퍼런스 효과(FGO·원신 등) 적용 금지.**

## 확정 진단 (코드 실증 완료 2026-07-13)
1. `draw/oripa_draw_screen.dart` `_buildExtract()` L378: `_coverCard`(검은 placeholder) 8장 겹침 + 상단 1장 `Offset(0, t*60)` + `scale 0.72→1.0` → 아래로 밀리며 튀는 등장.
2. `draw/reveal_view.dart` `SlabFrame`: 이미지 `186×260` 고정 → GRADED HERO 존재감 없음.
3. **route 겹침(확정)**: `/oripa/draw/:oripaId` 라우트가 `builder:` = GoRouter 기본 iOS 수평 슬라이드. `_extract.forward()`는 `initState` L82에서 **동기 호출** → 슬라이드 정착 전에 추출 애니 시작 → 좌우 밀림.

## 불변 계약 (건드리지 마)
- 구조 유지: `extracting→peeling→[N번 상품확인]→openingHeader→clues→HERO→heroHold→resultActions`.
- `reveal_view.dart` RevealView 상태머신 / `drawId` 계약 / `revealStarted`·`markRevealed` 타이밍 / `oripa_session.dart` 세션 계약 불변.
- 리빌 = 결과 안 바꾸는 표현층. 결과는 commit 시 확정.
- **전역 라우터 변경 금지**: 수정은 `/oripa/draw` 라우트 개별 `pageBuilder` + `oripa_draw_screen.dart` 내부로 한정(다른 화면 영향 0).

## 수정 범위 (Phase 1)
- 봉인팩: `_coverCard`를 포켓폴리오 오리파 전용 봉인팩/티켓으로 재설계.
- 모션: draw 라우트 개별 fade/무전환 `pageBuilder` + `_extract.forward()`를 route 정착 후(+80~120ms)로 지연. `_buildExtract` 중앙고정(`translateY 0→-8~-12`, `scale 0.96→1.00`)으로 교체.
- HERO: RAW=실이미지 `BoxFit.contain` 크게 / GRADED=`SlabFrame` 화면높이 58~68%.

## 승인 기준 (전부 충족해야 Phase 1 통과)
- [ ] pre-reveal 봉인물 NORMAL/HIT/GRADED **외형 완전 동일**
- [ ] 검은 placeholder + 임시 포켓볼형 아이콘 제거
- [ ] 봉인물 화면 폭 **62~70%**
- [ ] 추출 시작·완료 **카드 중심좌표 변화 ≤ 2px**
- [ ] `translateY +60` 및 `scale 0.72→1.0` 제거
- [ ] 더미→단일 팩 전환 **위젯 교체 점프 없음**(같은 key/rect/center)
- [ ] peel 시 바깥 커버 ↔ 내부 번호판 **레이어·재질 명확 분리**, 60%·82% 햅틱 유지
- [ ] RAW HERO 실이미지 **비율 유지·크롭 금지**, 크게
- [ ] GRADED HERO 화면높이 **58~68%**, BRG/PSA 라벨·등급 실기기 판독 가능
- [ ] draw 진입 시 좌우 슬라이드 겹침 제거(route 정착 후 추출)
- [ ] 같은 기기 **수정 전/후 영상 나란히 비교** 제출
- [ ] Phase 1 단계에서 레퍼런스 효과 미적용

## 절차
봉인팩+모션 수정 → 기준선 IPA 재빌드 → 실기기 녹화 → 전후 비교 → 승인 → Phase 2(레퍼런스). 복잡 UI는 Codex와 상의(CLAUDE.md).
레퍼런스 매핑·타이밍·프로필 상세: Claude memory `oripa-reveal-spec` 참조.
