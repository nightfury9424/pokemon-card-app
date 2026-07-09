# SNKRDUNK_JP 가격 파이프라인 (dry-run · 로컬)

scrydex JP 를 SNKRDUNK 일본 실거래로 **감시·검증·보정**하는 신규 보조 가격 소스.
설계 정본: [`docs/SNK_PRICE_PIPELINE_DESIGN.md`](../../../docs/SNK_PRICE_PIPELINE_DESIGN.md)

> ★ 전부 **dry-run / 로컬 SQLite**. prod DB write 0 · 가격 반영 0.
> scrydex 절대 덮어쓰지 않음 · approved override 만 사용 · 자동 적용 0.

## 구성 (구현 순서 ①~④)
| 모듈 | 역할 |
|------|------|
| `config.py` | 경로·환율(USD 1536.48 / JPY 9.50, 2026-06-29)·이상치 임계 |
| `db.py` | ① 로컬 SQLite 스키마: `approved_mapping` / `snk_snapshot`(=미래 price_snapshots `source='SNKRDUNK_JP'` 미러) / `review_queue` |
| `snk_client.py` | SNK sales-chart/detail fetch (403/429 즉시중단) |
| `load_mapping.py` | ② 승인게이트: working → approved (`approve`/`reject`) |
| `collector_dryrun.py` | ③ APPROVED 카드만 SNK 수집 → `snk_snapshot` |
| `detector_dryrun.py` | ④ `snk_snapshot` vs scrydex ladder → `review_queue` (PENDING_REVIEW) |

## 실행 (cwd = `python/price_v8`)
```bash
python3 -m snk_pipeline.db                                   # ① 스키마 init
python3 -m snk_pipeline.load_mapping load                    # working 3,314 적재(WORKING)
python3 -m snk_pipeline.load_mapping approve \
    --from-csv scrydex_jp_snk_replace_candidates_down_first.csv --col card_id --by <사람>
python3 -m snk_pipeline.load_mapping status                  # 승인 현황
python3 -m snk_pipeline.collector_dryrun                     # ③ approved 수집
python3 -m snk_pipeline.detector_dryrun                      # ④ 최신 run 이상치 검수큐
```
- `--include-working` (collector): 테스트 전용, 미승인까지 수집. **운영 금지.**
- `--limit N` (collector): 샘플 제한.

## 불변 원칙
- **working mapping ≠ approved.** 명시 `approve` 거친 것만 collector/override 투입.
- A(18)=raw 주력 / PSA10(22)·PSA9(23)=ladder 참고(raw 미혼입) / usedMinPrice=ASK 보조 / `all(-1)` 미수집.
- 정상 ladder = **PSA10 > PSA9 > RAW**. `priority=HIGH`(하향·저위험) 먼저, `LOW`(상향·고위험)는 강한기준.
- review_queue 는 전부 PENDING_REVIEW — **자동 적용 없음**. 사람 승인 후 override CSV(다음 단계).

## 검증 (2026-06-30)
HIGH 10(`down_first`) approve → 라이브 수집 → 디텍터가 **STRONG_REPLACE 10/10·HIGH 10/10** 독립 재현.
(분석 CSV 대비 일부 `n`/median 미세차 = 오늘자 1개월 윈도우 — 일일수집기 정상동작 증거.)

## 다음 (아직 미구현)
⑤ 검수 큐 UI(HIGH 10 먼저) → ⑥ approved override CSV → ⑦ GlobalPriceService 시뮬 → ⑧ 운영 반영(별도 세션·백업+승인).
저장소 결정(미결): price_snapshots `source` 추가 vs 별도 테이블 — 추천=source 추가(`snk_snapshot` 스키마가 그대로 이전됨).
