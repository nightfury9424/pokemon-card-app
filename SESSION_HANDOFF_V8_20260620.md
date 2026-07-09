# SESSION HANDOFF — v8 SNKRDUNK/KO (2026-06-20 새벽, 배터리저장)

## 한 줄 상태
SNKRDUNK catalog 스캔 **완료(41,610 포켓몬)** → 영구백업됨 → priority(14,089) 생성 → **다음=scanner 켜고 매칭 pilot 500**.

## ★백업 위치 (/tmp는 재부팅시 날아감 — 이게 영구)
`~/pokefolio_backups/snkrdunk_catalog_20260620/`
- snkrdunk_apparel_catalog_scanned.csv (41,610, md5 3ae51895…)
- apparel_scan_checkpoint.csv
- snkrdunk_apparel_catalog_priority.csv (14,089)
- snkrdunk_catalog_20260620.tar.gz / **tmp_full_backup.tar.gz (작업폴더 전체)**

### 재부팅 후 /tmp 복구
```
mkdir -p /tmp && tar -xzf ~/pokefolio_backups/snkrdunk_catalog_20260620/tmp_full_backup.tar.gz -C /tmp
```

## JP 트랙(SNKRDUNK) — 다음 할 일 (이어서)
1. 스캐너: `cd scanner && KMP_DUPLICATE_LIB_OK=TRUE /Users/fury/miniconda3/envs/scanner_v2/bin/uvicorn main:app --port 8082`
2. pilot 매칭 500:
```
cd /Users/fury/pokemon-card-app
python3 python/price_v8/snkrdunk_collect.py --match-and-collect \
  --catalog-csv /tmp/price_v8_snkrdunk_stage1_20260619/snkrdunk_apparel_catalog_priority.csv \
  --registered-csv /tmp/price_v8_snkrdunk_stage1_20260619/target_pokefolio_all_for_snkrdunk.csv \
  --limit 500
```
3. MATCH_HIGH 수 확인(priority top=신 M세트라 OUT_OF_SCOPE 많음, 옛 SR/SAR가 매칭) → 2000→10000→전체 확장
4. MATCH_HIGH만 sales-history → A/PSA9/PSA10 ladder → snkrdunk_evidence_mapped.csv (=JP evidence)

## KO 트랙
NAVER cardmvk = **v8 미사용 확정**(등급/일판/경매 오염, 삭제X 보관). KO ground truth = 당근/번장 한글판 RAW 단품(별도, 7요건 게이트:①한글판②단품③RAW④카탈로그존재⑤매핑확정⑥체결⑦이미지). naver_review/ 도구 보관.

## v8 모델 (합치는 건 최종 decision)
①KO체결 우선 → ②SNKRDUNK A급×KO/JP계수 → ③Scrydex fallback → 충돌/없음=검수중. 교차밴드±25%. 우선순위 MANUAL>FLOOR>FROZEN>v8. 로드맵=`V8_AFTER_CATALOG_ROADMAP.md`(6단계). v6 sync=23:45 PASS 안정.

## 핵심 파일
- 수집기: `python/price_v8/snkrdunk_collect.py` (scan완료/--match-and-collect/--catalog-csv 옵션)
- 로드맵: `V8_AFTER_CATALOG_ROADMAP.md`
- 메모리: project_price_v8_anchor_handoff_20260619 · project_v8_ko_ground_truth_naver_20260620

## 금지: prod write·자동가격·신규59·미등록수집·NAVER사용·v6/live.
