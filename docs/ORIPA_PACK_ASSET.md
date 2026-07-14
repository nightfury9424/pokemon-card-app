# 오리파 봉인 포일팩 — 시각 자산 확보 · Flutter 통합 준비

> 결정(2026-07-14): 팩 외형을 코드(HTML/CSS/SVG/CustomPainter)로 손제작하는 방식 **폐기**(4회 반려).
> 팩 그래픽 = 이미지 생성/디자인 산출물로 별도 확보 → Flutter는 **레이어 합성·애니만** 제어.
> Step 1 기술 기반(route 정착 후 추출·가로 드래그·60/82 햅틱·중심 고정) **보존**. `OripaSealedPack` 현재 외형 = 폐기 placeholder.
> **Step 2 미착수.**

---

## 0. 목표
"실제로 판매될 법한 트레이딩 카드 **부스터 포일팩**." 게임 UI·판타지 소품·화장품 파우치·비닐봉지 금지. 실사/3D 제품 렌더 기준.

## 0.1 핵심 프로세스 규칙 (지키지 않으면 애니에서 팩이 프레임마다 바뀜)
1. **상태별 독립 생성 금지.** 닫힌 팩만 A/B/C 3장 생성 → 1개 선택 → **그 동일 이미지를 편집(inpaint/마스킹)** 해서 나머지 레이어 파생.
2. **텍스트를 이미지에 굽지 않음.** POKEFOLIO/오리파명은 오탈자·상품별 가변 → 팩엔 **글자 없이 안전영역만**, 텍스트는 Flutter/SVG 오버레이.
3. **카드 뒷면은 팩 이미지에 합성 안 함.** Flutter 독립 레이어(상승 위치·크기·아우라 자유 제어).
4. **강한 반사광 굽지 않음.** 기본 자산은 재질+약한 고정 반사만. 이동 반사광은 Flutter 오버레이.
5. **누끼용 배경.** 중립 밝은 회색·균일 조명·그림자 없음. 앱의 검은 배경·그림자는 Flutter.
6. **비율 통일 = 0.605** (260:430 = 26:43). 원본 ≥ 1200×1985, 최종 780×1290(@3x).

---

## 1. 공통 프롬프트 (닫힌 팩 · 모든 변형 앞에 붙임)
```
Premium sealed trading-card booster foil pack, CLOSED, front-facing, standing upright, centered,
the FULL object fully visible, isolated on a neutral light-gray background with even soft studio
lighting and NO cast shadow (for easy cutout). Realistic foil pouch: FLAT with only a slight
thickness from the cards inside, straight clean heat-sealed vertical side seams, thin realistic
crimped (serrated heat-seal) top and bottom edges. NOT puffy, NOT inflated, NOT a plastic bag,
NOT a pouch. The front is a blank panel with a subtle abstract holographic pattern and NO text,
NO letters, NO logo, NO central gem or emblem — keep the top ~15% and the lower ~25% visually
calm and clean as empty safe areas for a wordmark and title to be overlaid later. Subtle realistic
foil texture with restrained static reflections only, NO dramatic diagonal light streak, NO strong
glare. Premium commercial product render, photorealistic, high detail.
```

**변형별 재질 (뒤에 이어붙임)**
- **A · 현실적 홀로 포일**: `Iridescent holographic foil with subtle cyan, magenta, teal and gold shifts over a deep midnight-indigo base, premium and tasteful, not gaudy.`
- **B · 다크 럭셔리 골드 포인트**: `Matte deep midnight-indigo to near-black foil with a thin restrained gold foil accent frame, understated luxury, minimal holographic shimmer only at the edges.` (골드는 **테두리 액센트만**, 글자 아님)
- **C · 미니멀 메탈릭**: `Brushed metallic silver-champagne foil, ultra minimal, near-monochrome, generous negative space, refined and clean.`

**Negative (공통)**
```
text, letters, words, logo, typography, numbers, watermark, central emblem, gem, crystal,
concentric circles, dark background, black background, cast shadow, dramatic light streak,
strong glare, puffy inflated pouch, plastic bag, cosmetic sachet, game UI, buttons, deformed,
blurry, cartoon, sticker
```

**Params**
- Midjourney: `--ar 26:43 --style raw`
- DALL·E / Nano Banana / SDXL: "portrait, ~0.605 ratio, ≥1200px wide, neutral light-gray background, even lighting, no shadow"
- 원본 최소 1200×1985 → 최종 앱 자산 780×1290로 다운스케일.

---

## 2. 이번 단계 산출 = **닫힌 팩만** (각 방향 2~3 seed)
이미지 생성은 같은 프롬프트도 편차가 크므로 **각 방향 2~3 seed** 생성 → 총 6~9장(부담되면 2장씩 6장). **전부 닫힌 팩만.** 형이 그중 **1개 선택**(Claude 승인 안 함). 상태 2·3 생성, Step 2 구현은 **아직 안 함.**

### 선택 기준(체크리스트)
- [ ] 한눈에 실제 트레이딩 카드 **부스터팩**으로 보이는가
- [ ] 평평·얇음, **과도한 부풀음 없음**
- [ ] 좌우 실링 + 상하 크림프가 현실적
- [ ] 포일 질감이 **화장품 파우치·비닐봉지 아님**
- [ ] 중앙에 임시 문양·보석·게임 UI **없음**
- [ ] 상단·하단에 **텍스트 안전영역** 있음
- [ ] 어두운 앱 배경에 놓아도 **외곽 분리(누끼) 가능**

---

## 3. 선택 후: 동일 이미지에서 레이어 파생 (편집, 독립 생성 아님)
선택된 닫힌 팩 1장을 기준으로 **편집(컷아웃/inpaint)** 해서:
| 레이어 | 만드는 법 | 비고 |
|--------|-----------|------|
| `pack_base` | 선택 이미지 누끼(투명 배경) | 히어로 |
| `pack_top_strip` | 상단 실링 스트립만 crimp 선 따라 분리 | Flutter가 절취/말림/제거 |
| `pack_open_body` | 같은 몸체에서 상단 제거 + 얇은 가로 슬롯 입구 inpaint | 절취 완료 후 |
| `pack_mouth_shadow` | 입구 내부 암부(가로 슬롯) | Flutter 그라디언트로 대체 가능 |
> 절취 규칙: 상단 실링을 **한쪽에서 얇게** · 중앙까지 세로 찢기 금지 · 큰 삼각 플랩 금지 · 조각 작게 말림 · 입구 = **얇은 가로 슬롯**.

**카드 뒷면 = 팩에 합성 안 함.** `card_back`은 Flutter 독립 위젯/자산으로 슬롯 중앙에서 넓게 상승.

---

## 4. Flutter 통합 스펙
### 4.1 캔버스·포맷
- 팩 **260×430 논리(2:3 아님, 0.605), @3x → 780×1290 px**. 모든 레이어 **동일 캔버스·동일 원점**(겹치면 정합).
- **PNG + 알파(투명)**. 파일명: `pack_base@3x.png` · `pack_top_strip@3x.png` · `pack_open_body@3x.png` · `pack_mouth_shadow@3x.png` · `card_back@3x.png`.
- 텍스트 없음 → 브랜드·오리파명은 Flutter Text/SVG 오버레이(상단·하단 안전영역).

### 4.2 정합 가이드
- **입구 슬롯 Y**: 팩 상단에서 높이의 12~15% 수평 슬롯.
- **카드 상승 rect**: 슬롯 중앙, 폭 ≈ 팩 폭 60%.
- 팩 중심 = 캔버스 중심(중심 고정 계약과 정합).

### 4.3 단계 ↔ 레이어
| 단계 | 활성 레이어 | 모션 |
|------|-------------|------|
| 등장 | `pack_base` (+ Flutter `foil_highlight` sweep) | center-anchored fade/scale-in |
| 절취(드래그) | `pack_base`→`pack_top_strip` 분리·말림 + `pack_mouth_shadow` 노출 | 한쪽부터 가로 절취, 작은 말림, 60/82% 햅틱 |
| 개봉 완료 | `pack_open_body` + `pack_mouth_shadow` | 상단 열림 |
| 카드 상승(Step 2) | `card_back` 상승 + 팩 하강 퇴장 | 슬롯 중앙 넓게 상승 |
| 아우라/HIT(Step 2+) | 팩 퇴장, `card_back`+후광 | 팩 발광 과하면 아우라 안 삶 |

- `foil_highlight`(이동 반사광)·`card_back`은 **Flutter에서 생성/제어**(이미지에 굽지 않음).

---

## 5. 절차
1. **닫힌 팩 A/B/C 3장 생성**(형).
2. **1개 선택**(형; Claude 승인 안 함).
3. 선택 이미지 → §3 레이어 편집 파생.
4. Claude가 `assets/oripa/` 배치 + §4 합성·애니 통합 + Step 1 메커닉 재부착.
5. 그 뒤 Step 2(카드 상승·아우라).
