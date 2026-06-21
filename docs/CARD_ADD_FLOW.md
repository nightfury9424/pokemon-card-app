# 카드 추가 플로우 (갭필 파이프라인) — 재사용 플레이북

> 신규/누락 카드를 **DB + 이미지 + 시세 + 스캐너**에 end-to-end 추가하는 표준 절차.
> 2026-06-22 **53장 추가**에서 확립. (카드 SET 통째 등록은 → `docs/CARD_SET_IMPORT_RUNBOOK.md` 별도. 이건 갭필=개별 다수.)

## 0. 정책 (현재 운영 기준 — 영구 규칙 아님)
- ★**일러스트 기준 1장만 유지 = 현재 갭필 운영 정책** (영구적 스캐너 기술 한계 아님). 지금은 스캐너가 같은 일러 다른 세트를 구분 못 해서 적용 — **스캐너 v2로 구분력 개선되면 재검토 가능**. 같은 일러 재판 = **KO 최초발매(확장팩) 유지 · 하이클래스팩(컴필) 제외**. 단 하이클래스팩이 KO 최초인 CHR/CSR(가디안 등)은 유지.
- 이미지 = scrydex JP. `image_url=NULL` (앱이 card_id로 CloudFront 조립).
- 가격 = KO_ESTIMATED = JP_raw × 환율 × 레어도계수 — ★**한국 실거래가 없는 신규 카드의 임시 bootstrap 방식** (확정 시세 공식이나 v8 최종 설계 아님; **v8 도입 시 교체 가능**).

## 1. 후보 → 퍼널  (`python/catalog_gapfill/`)
| 단계 | 도구 | 내용 |
|---|---|---|
| prod 중복 제거 | `scanner_dedup.py` | 후보 KO → **prod 스캐너 /identify** dup≥0.90 (앱에 이미 있는 일러 거름) |
| 후보끼리 재판중복 | `intra_dedup.py` | KO↔KO ≥0.92 ∪ 동일 JP/EN ref. 하이클래스팩=재판 제외 |
| JP/EN 재매칭 | `kotruth_rematch.py`·`en_rematch_dino.py` | **KO 원본 진실원**. JP<0.78 재매칭 + EN=pokemontcg.io vs JP. → 검수 HTML(`generate_rematch_html.py`) **사용자 승인 필수, 자동적용 X** |
- 산출: `final_NN_payload.json` (card_id·name·rarity·collection_number·jp_scrydex_ref·en_scrydex_ref·super_type·product_id)
- 2026-06-22 실적: 246→53 (UNRESOLVED 17·prod중복 50·보류EN 6·거부 2·재판 2)

## 2. 게이트 (read-only, write 前)
provenance(출처 승인·clean 0) · **prod 충돌 0**(card_id·jp_ref·en_ref) · payload SHA256 고정 · 이미지 존재

## 3. S3 업로드
`cards/v1/jp/{card_id}.png` (ContentType image/png, CacheControl immutable) → **CloudFront 200 검증 N/N**

## 4. DB 등록  (`python/catalog_import/import_card_set.py` 재사용)
- ★FROZEN_RTR이 stale/HIT_TOP → **런타임 오버라이드** = `audit/V6_BOOTSTRAP_SNAPSHOT_*.json` — ★**v6 출력과 동일함이 독립적으로 증명된 값이 아니라, 현재 v6 적용 결과와 충돌하지 않도록 맞춘 등록용 스냅샷**(기존카드 실효 적용값에 맞춤). 당근/ko_price_coefficients/어드민표시 전부 적용값과 불일치 → 부트스트랩 사용.
- **canary 1장 먼저**: 숨김 COMMIT + visible + 앱 검증 → 나머지 일괄
- **숨김(is_visible=false) 일괄 COMMIT** + 백필(SCRYDEX_JP RAW + KO_ESTIMATED chart_price) → 검증(레어도별 KO/JP=스냅샷·graded 0·기존 불변·price행 정확) → **visible=true**
- **v6 DRY_RUN=1** (write-0): would-change 0 = flip 없음 = 부트스트랩=v6 확인. ★**전역 v6 apply 금지**
- 도구: `apply_NN.py`·`canary_*.py`·`dryrun_NN.py`

## 5. 스캐너  (★full rebuild·build_db.py 금지)
- **운영 기준본(.bak) 복원** (prod와 faiss SHA 일치 확인) → `scanner/db/build_missing.py` 증분 (신규만, KO/JP/EN augment=15벡/장. ko는 `data/cards/{cid}_ko.png` 미리 다운, jp/en은 자동)
- 기존 벡터 **불변**(prefix 동일 검증)
- **로컬 게이트**: 집합 일치(DB↔스캐너 diff)·missing/orphan/<10=0·신규 self-match(KO/JP/EN)·**회귀셋 A/B(exact base 대비 신규회귀 0)**·맥날/탱탱겔
- **배포 = 블루-그린** `/admin/reload-index` (file:// staging, 토큰=컨테이너 env 참조·미출력, 검증 후 원자교체·무중단). 스캐너 인덱스 = `/opt/pokefolio/data/faiss/`(도커 `pokefolio-scanner`에 `/app/scanner/db` 마운트), nginx 재시작 불필요
- 운영 검증(3xxx·diff·맥날·가디안) 후 멈춤
- 도구: `scanner/gate_NN.py`

## 6. ★같은-포켓몬 회귀 주의 (중요)
- 신규 카드가 **같은 포켓몬 기존 카드 스캔을 끌어감**(V/ex/VMAX/AR). 클린은 구분되나 노이즈 스캔에서 뒤집힘 = **모델 한계**.
- 회귀 유발 신규 카드는 **스캐너 인덱스에서만 제외**(DB/앱/시세는 정상 노출) → `scanner/scanner_excluded_cards.json` allowlist → **hard-neg v2** 통과 시 복귀.
- ★빠른해결(OCR번호·rot+7제거·카드별 합의점수·실사진 augment 추가) **전부 실패 확인됨**(진단: 신규클린 > 정답실사진) → 근본 = 모델 v2. 분석도구=`scanner/ab_consensus.py`·`reg8_forensic.py`·`realshot_experiment.py`·`realshot_diag.py`.

## 요약 순서
후보 → ①dedup/rematch(승인 HTML) → ②read-only 게이트 → ③S3 → ④DB(canary→일괄, v6 DRY_RUN) → ⑤스캐너(build_missing→블루그린→게이트) → ⑥회귀시 제외+allowlist
