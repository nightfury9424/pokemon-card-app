# KO 시세 파이프라인 건강검진 리포트 — 2026-06-16

> **목적: 특정 카드 가격 보정이 아니라, 시세 시스템이 어디서 오작동하는지 탐지·감시.**
> 진단기 = `scripts/price_health_report.sql` (READ-ONLY, prod write 0). 변경 전/후 매번 실행해 before/after 비교.

## 실행
```bash
ssh -i /Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120 \
  "docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -A -F'|'" \
  < scripts/price_health_report.sql
```

## 오작동 판정 규칙 (해석 가이드)
1. `audit`(ko_estimation_audit.ko_price)는 **truth 아님** = 23:45 stage-2 모델값(overlay 전 디버그값).
2. **audit ≥ 2×live = 복구 대상 아님 = LANDMINE**(복구하면 인플레). live가 overlay 교정값.
3. `selected_source='EN'`인데 JP raw 존재 = **spread가드 JP→EN flip = JP-first 위반.**
4. DAANGN obs 있는 카드는 계수/v6/sanity가 덮으면 안 됨(실관측 우선).
5. MANUAL_ANCHOR / card-scope coef 는 rarity 계수보다 우선.
6. `sanity_fire`(오늘밤 sanity_cap 발동)가 임계↑면 배치 abort 후보.
7. visible rarity 중 audit≥2×live 비율 50%↑ = **계수 과대 후보(SUSPECT_COEF)**.
8. `price_summaries`(복수)=실거래 집계, 현재가 경로 아님. 현재가=`getCardPriceSummary`(@Cacheable 30m TTL).

---

## 📊 현재 스냅샷 (2026-06-16)

### [1] OVERALL (비프로모 3,711장)
| total | visible | **audit≥2×live (landmine)** | live≥2×audit (이상) | DAANGN | card-scope | manual-anchor | **EN-flip(JP존재)** |
|---|---|---|---|---|---|---|---|
| 3,711 | 3,427 | **726** | 5 | 243 | 29 | 18 | **1,374** |

### [2] PER-RARITY (status)
| rarity | n | vis | live_med | audit2x | 관측 KO/JP | DAANGN | card-scope | sanity_fire | status |
|---|---|---|---|---|---|---|---|---|---|
| SR | 1002 | 1001 | 2,710 | 64 | 0.332 | 60 | 6 | 0 | OK |
| RR | 960 | 960 | 465 | 45 | 0.471 | 19 | 0 | 0 | OK |
| **AR** | 522 | 522 | 1,940 | **356** | 0.263 | 29 | 5 | 8 | **SUSPECT_COEF** |
| S | 258 | 0 | 970 | 127 | 0.399 | 2 | 1 | 0 | HIDDEN |
| SAR | 237 | 237 | 11,270 | 45 | 0.307 | 72 | 13 | 1 | OK |
| HR | 181 | 181 | 3,880 | 13 | 0.157 | 13 | 0 | 0 | OK |
| **CHR** | 54 | 54 | 2,355 | **54(100%)** | 0.399(n1) | 1 | 0 | 0 | **SUSPECT_COEF** |
| (RRR/PR/UR/SSR/SM-P/CSR/MA/MUR/BWR) | — | — | — | 0~14% | 0.27~0.82 | — | — | 0 | OK |
| A(13)·K(12) | — | 0 | — | — | — | — | — | — | HIDDEN |
- **유저 노출 계수 과대 = AR + CHR 둘.** 나머지 visible rarity OK. CHR 계수 JP1.12 vs 관측 0.399 = 2.8배 과대.

### [3] LANDMINE TOP (audit≥2×live, 복구 절대 금지)
블래키 ex SAR 228,400/audit 546,963 · 님피아VMAX HR 95,240/393,575 · 파이리 AR 13,046/69,072(EN 5.3×) · 피카츄 CHR 60,930/171,971(2.8×) … (대부분 EN-flip 또는 manual-anchor가 모델보다 낮게 설정된 정상 케이스. **audit로 복구 시 전부 2~6배 인플레.**)

### [4] SPREAD-FLIP TOP (selected_source=EN인데 JP존재, 1,374장)
블래키 ex SAR EN/JP 3.5× → audit 546,963 · 메가망나뇽 SAR 2.9× · 리자몽GX SSR 3.2× … **spread가드가 높은 EN을 골라 audit 인플레.** JP-first 위반의 실체.

### [6] SANITY_FIRE TONIGHT (다음 배치에서 sanity_cap 발동 예정 9장)
🚨 **모야모 SAR 148,800 → cap 36,953** (MANUAL_ANCHOR인데 보호 안 됨) + AR commons 8장(모부기/리오르/메리프/파비코/포챠나/해골몽/비버니/란쿨루스, en_p75=0.114 캡).

### [7] LIVE≥2×AUDIT (overlay가 모델보다 올린 5장)
모야모 SAR 148,800/audit 23,748 · 팬텀&따라큐 GX SR 95,130/29,681 · 난천 SR 71,530 · 뮤 ex SAR 70,000 · 피카츄&제크로무 GX SR 34,320. (전부 manual-anchor/floor = 정상, 단 sanity 충돌 주의.)

---

## 🚨 탐지된 오작동 (우선순위, auto-fix 안 함)

| # | 오작동 | 영향 | 조치(승인 필요) |
|---|---|---|---|
| **1** | **sanity_cap이 MANUAL_ANCHOR 모야모(148,800)를 다음 배치에 37k로 크러시.** held 리스트(14) ≠ MANUAL_ANCHOR(18). | 수동앵커 파괴 | sanity held에 MANUAL_ANCHOR 18 추가 OR sanity가 manual/card-scope 제외. **+ 밤 배치 실행여부 확인**(live traded_at=6/14 → 일시정지 의심) |
| 2 | AR·CHR 계수 과대 (SUSPECT_COEF) | audit 인플레·landmine | AR JP→0.16, CHR JP 1.12→~0.4 (ground truth 보강) |
| 3 | spread가드 JP→EN flip 1,374장 | audit 인플레(JP-first 위반) | GlobalPriceService:2297 — JP있으면 JP고정 |
| 4 | audit≥2×live 726장 | 복구 시 인플레 | **audit 복구 영구 금지 명문화** |
| 5 | card-scope placeholder coef=1.0 (명희의격려 SR·빛나 SR·레어코일 S) | KO=raw 비현실 | card-scope stale 정리 |
| 6 | AR commons 8장 매일 sanity 재캡(en_p75=0.114) | cheap AR 과소 | AR 계수 재보정 후 sanity AR en_p75 폐기/재평가 |

## ⚠️ 진단기 한계 (다음 보강)
- `v6_next_price`(v6_apply 다음 출력)는 Python 로직이라 SQL 미구현 → 별도 DRY_RUN 필요.
- 관측 KO/JP는 DAANGN VALID 180일 기준(thin rarity는 n낮음, CHR n=1).
- price_summaries(차트) staleness는 30분 TTL 자가해소라 미포함.

## 다음
- AR/CHR 계수 보정·spread가드·sanity 보호는 **이 리포트 기준 + Codex 사후리뷰 후** 진행. 변경 후 이 스크립트 재실행해 before/after.
- 상위 진입점: [PRICE_RECOVERY_HANDOFF_20260616.md](PRICE_RECOVERY_HANDOFF_20260616.md)
