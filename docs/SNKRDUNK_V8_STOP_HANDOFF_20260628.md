# SNKRDUNK V8 — OLL STOP HANDOFF (2026-06-28)

> **2026-06-28 SNK 작업 의도적 중단.** 작업이 본래 목표(기존 카드 JP 가격소스 대체)에서
> 신규 프로모 추가/독점 프로모 분류라는 **다른 프로젝트**로 번져서 올스탑. 안드로이드 준비로 전환.

## 0. 본래 목표 (재확정)
```
scrydex JP 값 신뢰도 낮음 (AR 계수 과대·ground truth 부재)
 → SNKRDUNK 일본 실거래(sold) 데이터 수집
 → 우리 기존 카드에 SNK apparel_id 매핑
 → JP 가격 소스만 SNK로 대체 (신규 카드 추가 아님)
 → EN 은 scrydex 유지
```

## 1. 확정 결론 (정책)
- SNKRDUNK 작업의 본래 목표 = **신규 카드 추가가 아니라 기존 카드의 JP 가격 소스 보강.**
- **JP 가격 소스 정책:**
  - JP = **SNKRDUNK SOLD JP 주력**
  - SNK 매핑 없는 카드 = **scrydex JP fallback**
  - EN = **scrydex EN 유지**
- **missing promo / 독점 프로모 / 신규 카드 추가 = 별도 백로그.** 지금 진행 안 함.
- prod DB write 0 · 가격 DB 적재 0 · 확정 검수 전 SNK mapping 적용 0.

## 2. 달성한 것 (성과)
1. **SNK catalog 41,610 포켓몬 apparel 확보·영구백업** (`~/pokefolio_backups/snkrdunk_catalog_20260620/`).
2. **스캐너(이미지) 매핑 방식 검증** — SNK 41,610 이미지를 우리 스캐너 `/identify_path`로 판별 → 우리 등록 3,755 카드로 떨어지는 후보 추출. 세트코드 alias 우회.
3. **우리 3,755 중 3,622(96.5%) 후보 잡힘** (REGISTERED_TOP1 12,635 row · OUT_OF_SCOPE 28,912).
4. **EN/JP 구별** — `英語版`/`[EN]` 마커로 EN 후보 제외(JP만).
5. **JP=SNK / EN=scrydex 방향 명확화.**
6. 검수 앱(로컬 FastAPI+SQLite, 실시간 저장) + 위험군 탭(프로모위험/번호DIFF/저점수 등) 구축. 매핑 판정 **115건** 저장됨(보존).

## 3. 보존 산출물 (삭제 금지)
| 파일 | 내용 |
|---|---|
| `~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv` | ★41,610 SNK 포켓몬 catalog (source of truth) |
| `python/price_v8/snk_scan_results.jsonl` | 41,610 전체 스캔 결과(top1/top5) |
| `python/price_v8/snkrdunk_full_image_scan_results.csv` | 전체 스캔 로그(버킷) |
| `python/price_v8/snkrdunk_registered_image_candidates.csv` | 우리 카드로 떨어진 후보 12,696 |
| `python/price_v8/snkrdunk_review.sqlite` | SNK 매핑 검수 판정 DB (115건) |
| `python/price_v8/snkrdunk_missing_promo_candidates.csv` | 우리 DB 없는 프로모 후보 2,588(백로그) |
| `python/price_v8/snkrdunk_missing_promo_review.sqlite` | 프로모 추가 검수 DB(백로그) |
| 스크립트 | `snkrdunk_full_scan.py` · `snkrdunk_build_review.py` · `snkrdunk_review_server.py` · `snkrdunk_review_app.html` · `snkrdunk_missing_promo*.py/.html` |

## 4. 재개 방법 (나중에)
```bash
# SNK 매핑 검수 재개:
/Users/fury/miniconda3/envs/scanner_v2/bin/python python/price_v8/snkrdunk_review_server.py   # :8787
# 검수 끝나면 → 확정 매핑(APPROVED)만 → SNKRDUNK_SOLD_JP 승격 → v8 JP 앵커
```
- **재스캔/재인덱싱은 신규 카드 추가했을 때만 필요** (지금 안 함).
- missing promo 백로그 재개: `snkrdunk_missing_promo_review_server.py` (:8788). **단 이건 출시 후.**

## 5. 다음 = 안드로이드 준비
- 원래 iOS 심사 기간에 하기로 한 작업 = **안드로이드 출시 준비** (master flow 3트랙 중 ③).
- SNK는 백로그. 안드로이드와 **섞지 말 것.**

## 6. 금지
- 프로모 추가 진행 · missing promo 계속 검수 · HIGH_AUTO 일괄승인 · SNK 매핑 prod 반영 · 가격 모델 반영 · 안드로이드와 SNK 작업 혼합.
