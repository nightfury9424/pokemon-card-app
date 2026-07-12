# 오리파 리빌 Phase 1 — 승인된 구조 v4 (구현 스펙)

> 저장소 진실원. 스토리보드 **v4 승인·잠금 (2026-07-13)**.
> 승인 시안(저장소 내): [`docs/assets/oripa/reveal_storyboard_v4.html`](assets/oripa/reveal_storyboard_v4.html) · [`docs/assets/oripa/reveal_storyboard_v4.png`](assets/oripa/reveal_storyboard_v4.png)
> 폐기: v1(실버 보안봉투 + 팩 아래로 벗겨 번호판 노출), v2(옆면 카드 옆 문구). **본 문서엔 v4 구조 하나만 존재한다.**

---

## 1. 승인된 리빌 흐름 (경로별)

경로(path)는 **의미적 유형**이 결정한다. `intensity`(아우라 강도)로 추론하지 않는다 → §3.

### NORMAL 경로
```
닫힌 카드팩 → 상단 절취(탭 옆으로) → 카드 뒷면 상승(후광 없음, 팩 잔해 없음)
→ [카드 탭 또는 "N번 상품 확인하기"] → 일반 플립(~320~420ms) → 바로 앞면 공개
```
암전·문구·"꽝" 없음. 최소 조명만.

### HIT 경로
```
닫힌 카드팩 → 상단 절취 → 카드 뒷면 상승 + [금빛 후광]
→ [카드 탭 또는 "N번 상품 확인하기"] → 전체 화면 암전(카드·팩 화면에서 퇴장)
→ 검은 무대에서 문구 1개씩 (이전 사라지고 다음, 누적 금지):
   RAW:    세트 → RAW → 레어도 → 이름
   GRADED: 세트 → 회사 → 등급숫자 → 레어도 → 이름
→ 짧은 정적 → 중심광 → 빛 폭발 → 밝아지며 실제 카드/슬랩 앞면 HERO 첫 등장(후광 뒤에 정착)
```

플립 전까지 팩·뒷면·상승 안무는 **NORMAL/HIT 동일, 후광 유무만 차이**. 앞면은 (HIT는) 문구가 끝난 뒤 첫 노출.

---

## 2. 두 축 분리 — 경로(path) ≠ 아우라(tier) **[신규 계약]**

`intensity`는 원래 **연출 강도**축이다. 이걸로 NORMAL/HIT 경로를 판단하면 안 된다.

| 축 | 결정하는 것 | 값 | 발급 |
|----|------------|----|------|
| **리빌 경로 (path)** | 암전·문구·빛폭발 vs 담백 플립 | `normal` / `hit` | 정책이 **별도** 발급 |
| **아우라 tier** | 뒷면 후광의 광량·범위·입자 | `RevealIntensity {normal, rare, hit, jackpot}` | 정책 발급 |

**아우라 tier → 시각 매핑** (차등 = 광량·범위·입자, **색 아님**. 세븐나이츠식 카드 뒤 금빛 후광 + 소프트 번짐 + 골드 보케. 얇은 링/네온 금지):
- `normal` → 후광 없음 (스토리보드 라벨 "none")
- `rare` → 얇은 금빛 후광 + 약한 입자 (스토리보드 라벨 "hit")
- `hit` → 넓은 광륜 + 보케 다수 (스토리보드 라벨 "premium")
- `jackpot` → 폭발형 후광 + 광선 + 강한 발광

> ⚠️ **명칭 충돌 주의**: 스토리보드 푸터는 tier를 `none/hit/premium/jackpot`으로 라벨링하지만 **코드 enum은 `RevealIntensity.normal/rare/hit/jackpot`가 진실원**이다. `RevealIntensity.hit`(3번째 tier)와 **리빌 경로 `hit`**(암전 연출)는 **다른 개념**이다. 코드에선 `RevealPath.hit` vs `RevealIntensity.hit`로 타입 분리.

### 현재 모델 갭 + 요구 변경 (구현 step 3)
- 현재 `reveal_models.dart`엔 **경로 축이 없다.** profile은 `numberedConfirmRaw/Graded`뿐 → 싼 RAW 카드도 `numberedConfirmRaw` + `intensity==normal`을 받는다. 즉 경로 신호가 `intensity` 하나뿐.
- `RevealPolicy.intensityFor()`는 `effectsEnabled==false`면 **전부 `normal` 반환** (`reveal_models.dart:66`). → intensity로 경로를 추론하면 운영 플래그 하나에 HIT가 통째로 NORMAL로 붕괴.
- **따라서**: `RevealDescriptor`에 정책 발급 경로 신호(`RevealPath path` 또는 `bool isHit`)를 **추가**한다. `intensity`와 독립 발급.
- **불변식 (문서·테스트로 증명)**: 정책이 `path==hit`을 발급하면 정상 운영에서 `intensity >= rare`. 아우라를 운영상 낮춰도(심지어 `normal`) **경로는 바뀌지 않는다**(연출은 유지, 뒷면 후광만 사라짐). 테스트: `path==hit && intensity==normal`이 경로 분기를 NORMAL로 되돌리지 않음을 assert. 경로 분기는 `intensity`가 아니라 `path`만 참조함을 assert.

---

## 3. 카드 뒷면 입력 계약 (CTA / 오너 락) **[신규 계약]**

카드 뒷면 상태에서 리빌을 시작하는 입력은 **둘**이며 **동일한 exactly-once 핸들러**를 호출한다:
- 카드 뒷면 **탭**
- **"N번 상품 확인하기"** 버튼 탭

```
_beginRevealOnce():
  1) 이미 시작됨(guard) 또는 stale drawId → 무시 (중복 탭·연타 차단)
  2) markRevealStarted(drawId)   ← 첫 동작, 애니/await 前
  3) NORMAL/HIT 경로 분기
```

- `markRevealStarted` = **사용자 플립 시작 순간** (예전엔 버튼 탭이었음 — 이제 카드 탭도 동일 경로).
- `markRevealed` = **앞면 HERO 완전 노출 후**.
- 버튼을 완전히 제거하는 것은 단순 UI가 아니라 **오너 락 계약 변경**이므로 Phase 1 범위 밖. Phase 1은 버튼 **유지** + 카드 탭 **추가**(둘 다 같은 핸들러).

---

## 4. reduceMotion 계약 (OS 접근성) **[신규 계약]**

`reduceMotion`이어도 **결과 즉시 공개 금지**. 안무 축소는 하되 순서·pacing·콜백 계약은 유지:
- 절취·상승 **이동 축소**(순간 전환/짧은 페이드)
- 아우라 = **정적 소프트 후광**(입자·애니 없음), tier 차등은 광량으로만
- NORMAL 플립 = 페이드/크로스페이드 허용(회전 생략 가능)
- HIT = 문구 순서·암전·정적·HERO hold **유지**(빛폭발만 정적 플래시로 축소)
- `heroHoldMinMs` 등 pacing 유지 → 결과 직행 금지

---

## 5. 불변 계약 (건드리지 마)
- `reveal_view.dart` RevealView 상태머신 / `drawId` 계약 / recovery(committed/revealed) 계약.
- `markRevealStarted`(플립 시작)·`markRevealed`(HERO 완전 노출 후) 타이밍, exactly-once 콜백(`onHeroShown`/`onResultReady`).
- HIT 여부·intensity = `RevealDescriptor`(정책 발급). 클라가 가격/레어도로 자체 계산 금지, 운영 down/off 가능.
- 전역 라우터 변경 금지 — 수정은 `/oripa/draw` 라우트 개별 `pageBuilder` + `oripa_draw_screen.dart` 내부로 한정(타 화면 영향 0).
- 리빌 = 결과 안 바꾸는 표현층. 결과는 commit 시 확정.

---

## 6. Phase 구분
- **Phase 1 (이번)** = v4 **핵심 안무·기능 구현**: 상단 절취, 뒷면 상승, HIT 아우라(4 tier), 전체 암전, 단일 문구(누적 금지), 중심광·빛 폭발, HERO 첫 등장, NORMAL 담백 플립, 경로/아우라 2축 분리, CTA 이중입력·reduceMotion 계약.
- **Phase 2 (다음)** = 실기기 기반 **고급 튜닝**: 사운드, 햅틱, 입자 밀도, 타이밍, 광량. (Phase 1에 이미 세나식 아우라·암전·문구·빛폭발이 포함되므로 "레퍼런스 미적용"이라는 구분은 폐기 — Phase 경계는 *구현 vs 튜닝*이다.)

### 구현 중 1차 조정 4가지 (실기기 녹화로 튜닝 — Phase 2 성격)
1. HIT 아우라 = 외곽선 강조 아니라 **카드 뒤 공간 전체 금빛 후광 중심**.
2. HERO 카드 **존재감 크게** — 보상카드 먼저, 버튼 시선 덜.
3. NORMAL 앞면 **담백** — 후광/광폭발 금지, 최소 조명.
4. HIT 타이밍 **절대 겹침 금지**: 탭→암전→퇴장→문구 1개씩→정적→중심광→폭발→HERO.

---

## 7. 파일
- `front/lib/features/oripa/draw/oripa_draw_screen.dart` — 스테이지·팩·상단 절취·뒷면 상승·CTA·플립 트리거
- `front/lib/features/oripa/draw/reveal_view.dart` — 상태머신·경로 분기·검은무대 문구·빛폭발·HERO
- `front/lib/features/oripa/data/reveal_models.dart` — RevealDescriptor(+경로 축)·intensity·RevealConfig·정책
- `front/lib/features/oripa/oripa_common.dart` · `data/oripa_prizes.dart`

## 8. 승인 기준 (전부 충족해야 Phase 1 완료)
- [ ] 상단 절취 개봉(팩 중앙 고정), 카드 뒷면 상승, **팩 잔해 안 남김**
- [ ] 뒷면 후광 유무·tier로 아우라 차등(뒤집기 전) — 광량·범위·입자만, 색 동일
- [ ] 경로 분기는 `path` 축만 참조(테스트로 증명), `intensity`로 추론하지 않음
- [ ] 카드 탭 = "N번 확인" 버튼 = 동일 exactly-once 핸들러, 첫 동작 `markRevealStarted`
- [ ] NORMAL: 후광·암전·문구·"꽝" 없이 담백 플립
- [ ] HIT: 암전 → 문구 **1개씩**(누적 금지) → 정적 → 빛폭발 → 앞면 HERO
- [ ] HIT 프레임 05~11 타이밍 겹침 없음
- [ ] HERO 카드 존재감(RAW `BoxFit.contain` / GRADED 슬랩 화면높이 58~68%)
- [ ] reduceMotion: 축소하되 순서·hold·콜백 유지, 결과 직행 금지
- [ ] 상태머신·drawId·recovery·markReveal* 계약 유지, `flutter analyze` 클린, 테스트 통과
- [ ] 기준선 IPA 실기기 전/후 영상 비교

## 9. 구현 순서 (리뷰 가능하도록 분할)
1. draw route fade + 팩 / 상단 절취 (`_buildExtract`/`_buildPeel` 교체, `_coverCard` 폐기)
2. 카드 뒷면 상승 + 아우라(tier별) 위젯
3. NORMAL/HIT 경로 분기 + 검은 무대 (모델 경로 축 추가 + 정책 발급 + `_beginRevealOnce`)
4. HERO 반응형 크기 + recovery 경로별 검증
5. 테스트(경로/불변식/exactly-once) + `flutter analyze`

## 10. 절차
v4 잠금 → **문서 정합성 커밋(현재)** → 위 1~5 단계 구현 → analyze/test 클린 →
**모든 단계·테스트 통과 후에만** 기준선 IPA 빌드 → 실기기 녹화 → 4개 조정 튜닝 → 승인 → Phase 2.
복잡 UI·모델 변경은 Codex와 상의(CLAUDE.md).
