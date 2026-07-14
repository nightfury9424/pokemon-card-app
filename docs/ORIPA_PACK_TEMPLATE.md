# 오리파 팩 템플릿 카탈로그 — PackVisualConfig 설계

> 결정(2026-07-14): 팩을 포켓폴리오가 하나로 못박지 않는다. **플랫폼이 검수·제공하는 템플릿 카탈로그**에서
> 사장님이 고르고 매장 로고·오리파명을 얹는다. 팩 외형(`PackVisualConfig`)과 리빌 정책
> (`RevealDescriptor`/`RevealPolicy`)은 **절대 분리**. 관련: [[oripa-reveal-spec]] · `ORIPA_PACK_ASSET.md`(자산/레이어) · `ORIPA_REVEAL_PHASE1.md`(리빌 계약).
> ⚠️ 백엔드·파트너센터 UI는 복잡 로직 → 구현 전 Codex 상의(CLAUDE.md). 이 문서 = 설계 확정용, **코드 미착수.**

---

## 1. 생성 플로우
```
사장님 오리파 생성 → 팩 템플릿 선택 → 매장 로고/대표이미지 업로드 → 오버레이 미리보기
→ 관리자 검수 → 승인 → LIVE(PackVisualConfig 버전 스냅샷 고정)로 공개
```

## 2. 권한 분리 (핵심 계약)
| 사장님이 설정 (PackVisualConfig) | 서버/관리자 전용 (RevealDescriptor/RevealPolicy) |
|---|---|
| `templateId` (템플릿 선택) | HIT 여부 / NORMAL·HIT 경로 |
| 매장 로고 (`merchantLogoUrl`) | 아우라 tier(normal/rare/hit/jackpot) |
| 오리파명 (`oripaTitle`) | jackpot 연출·빛 폭발 강도 |
| 선택적 중앙 대표이미지 (`merchantArtworkUrl`) | 검은 무대·문구 순서·암전 강도 |
| accent (제한된 포인트 색) | 리빌 강도 전반 |

**둘을 절대 섞지 않는다.** 사장님은 **팩 외형까지만**. HIT·아우라·연출은 전부 서버/관리자.

## 3. 스포일러 금지 불변식 (리빌 계약과 정합)
- 같은 오리파에서 **NORMAL / HIT / GRADED HIT 모두 개봉 전까지 동일 팩·동일 로고**.
- "좋은 상품만 금색 팩"처럼 **결과별 팩 차등 금지** — 뜯기 전 결과 유출.
- HIT 전조는 **카드 뒷면이 나온 뒤 아우라에서만** 시작(기존 [[oripa-reveal-spec]] 계약 유지).
- ∴ `PackVisualConfig`는 draw 결과(`RevealDescriptor`)와 **무관**하게 오리파 단위로 고정.

## 4. 데이터 모델
```dart
enum PackTemplateId { pfHoloA, pfNavyGoldB, pfSilverC } // 승인된 템플릿(확장 가능)
enum PackAccent { gold, azure, magenta, silver }         // 플랫폼 제공 포인트색(제한)
enum PackVisualStatus { draft, adminReview, approved, live } // 승인 게이트

class PackVisualConfig {
  final PackTemplateId templateId;
  final String? merchantLogoUrl;     // 매장 로고(오버레이, 이미지에 안 굽음)
  final String? merchantArtworkUrl;  // 선택 중앙 대표이미지
  final String oripaTitle;           // 오리파명(오버레이)
  final PackAccent accent;
  final PackVisualStatus status;
  final int version;                 // LIVE 시 스냅샷 버전
  final bool isCustom;               // 커스텀 업로드 여부(=검수 강함)
  final String? customPackUrl;       // 커스텀 모드일 때만
}
```
- **LIVE 스냅샷**: 공개 시점의 `PackVisualConfig`를 version으로 고정. 판매 중 로고·이미지·템플릿 변경 = **재승인 후 새 version**(진행 중 오리파 팩이 갑자기 안 바뀜).

## 5. 기본 모드 vs 커스텀 모드
### 기본 모드 (권장·안전)
플랫폼 템플릿 + 로고·오리파명 오버레이만. **이미지 본체에 글자 안 굽음**(오탈자·상품별 가변 방지). 즉시 미리보기, 검수 간소.

### 커스텀 모드 (별도 옵션 · 관리자 승인 필수)
사장님 제작 팩 이미지 업로드 가능하되 검수 통과해야 적용:
- 지정 비율(0.605)·안전영역 준수, **상·하단 절취 영역 가리지 않음**
- 카드/당첨 결과·희귀도 **암시 금지**
- Pokémon 공식 로고·카드 일러스트 등 **저작권 위반 자산 금지**
- 과도한 문구·가격·당첨확률 문구 제한
- 개봉 애니 **레이어 규격 준수**(`ORIPA_PACK_ASSET.md` §4)
- **업로드 즉시 적용 아님 → 검수 후 적용**

## 6. 오버레이 안전영역 (팩 전면, 260×430 논리 / @3x 780×1290)
| 영역 | Y (팩 높이 %) | 용도 | 제약 |
|------|--------------|------|------|
| 상단 크림프·절취 **exclusion** | **0–15%** | **완전 비움 — 텍스트/로고 금지** | `pack_top_strip`이 뜯겨나감(브랜딩 걸치면 잘림) |
| `POKEFOLIO` 워드마크 | **18–25%** | 고정 오버레이 | 소형·중앙 |
| 매장 로고 / 대표이미지 | **30–55%** | `merchantLogoUrl` / `merchantArtworkUrl` | 박스 ≤ 폭 60% |
| 오리파명 | **72–84%** | `oripaTitle` | ≤ 폭 72%, 최대 2줄 |
| 하단 크림프 | 90–100% | **비움** | 콘텐츠 금지 |
- 좌우: 콘텐츠 x 10–90%(실링 seam 침범 금지). B 템플릿은 골드 프레임 내부(약 x12–88%)에 배치.
- **브랜딩 고정 규칙(중요)**: `POKEFOLIO`·매장 로고·오리파명은 전부 `pack_base`/`pack_open_body`의 **고정 오버레이**. 뜯기는 `pack_top_strip`엔 **브랜딩 0(순수 포일)**. 절취 중 브랜드 요소는 **제자리 고정** — 조각에 안 따라감/안 잘림. **3 템플릿 + 커스텀 업로드 모두 동일 상단 exclusion(0–15%) 강제.**

## 7. 초기 템플릿 (승인본 3종)
| templateId | 자산 | 성격 | 비고 |
|---|---|---|---|
| `pfHoloA` | `docs/assets/oripa/templates/pf_holo_a.png` | 홀로 포일(화려) | 중앙 홀로줄 → 텍스트는 상/하 영역 위주 |
| `pfNavyGoldB` | `docs/assets/oripa/templates/pf_navy_gold_b.png` | 딥네이비+골드프레임(프리미엄) | 중앙 깨끗·아우라 안전·재사용 최적 |
| `pfSilverC` | `docs/assets/oripa/templates/pf_silver_c.png` | 미니멀 실버 | 어두운 무대 분리 최적 |
> 현재 자산 = 9-up 그리드에서 크롭한 **프리뷰**. 확정 시 각 템플릿 **풀해상도 단독 렌더 재출력 + 컷아웃 + `ORIPA_PACK_ASSET.md` §3 레이어 파생** 필요.

## 8. 절차
1. (이번) 템플릿 3종 자산 정리 + 안전영역 + 파트너센터 미리보기 UI 설계.
2. 아키텍처 승인 → `PackVisualConfig` 모델·검수/버전 백엔드 스펙(Codex 상의).
3. 선택 템플릿 풀해상도 재출력 → 레이어 파생 → Flutter 리빌 통합.
4. 파트너센터 팩 편집·미리보기·검수 제출 UI 구현.
