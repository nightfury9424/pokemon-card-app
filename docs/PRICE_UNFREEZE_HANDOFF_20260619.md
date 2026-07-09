# 시세 동기화 un-freeze 인수인계 — 2026-06-19

> **다음 세션 시작점.** 먼저 이 문서 + 메모리 `project_price_sync_logperm_footgun_20260619` 읽어라.
> 보고는 **말 금지, 증거(파일/라인/diff/dry-run/rollback/crontab/카드값)로만.**

---

## TL;DR (현재상태 — 05:02 KST 검증 기준)

**오늘 23시 전 목표 = 운영 동기화 정상화 + P0 폭탄 제거 = 완료·라이브.**
남은 단 하나 = **오늘밤(2026-06-19) 23:45~23:57 첫 정규 live run 관측.** 그 전엔 손대지 말 것.

- 세션 재개가 **23:57 이전** → 할 것 없음. 대기.
- 세션 재개가 **23:57 이후** → 아래 "오늘밤 검증" 절차 1회 실행 → 통과면 사이클 종료.

---

## 0. 사건 개요 — 왜 이 작업을 했는가 (시작점 + 급성/만성 분리)

**6/18 mass spike만 보고 시작한 게 아니다. 시작점은 6/14→6/15 데이터 깨짐이다.**

**스모킹건 (이번 세션 DB 검증) — KO_ESTIMATED 일자별 생성 카드수:**

| 날짜 | KO_ESTIMATED 생성 | 판정 |
|---|---|---|
| 6/10~6/14 | 약 3,744장 | 정상 |
| **6/15** | **5장** | **부분실패 (스모킹건)** |
| 6/16~6/18 | 약 3,749장 | 생성 *수*는 복구. **단 6/18은 값 품질 별도**(생성 수 정상이어도 v6 미실행으로 값 spike) |

→ 최초 이상징후 = "6/15 단일일 KO_ESTIMATED 부분실패". 추적 중 나온 가설(prevSource flip / EN 과선택 / 계수 인플레 / graded 오염 / 24장 사각지대 / 새 모델 필요)은 **대부분 하류 증상**이고, 구조는 두 층이다:

| 구분 | ROOT | 이번에 해결? |
|---|---|---|
| **급성** (6/18 mass spike) | v6 로그 권한 풋건 → 23:52 v6가 `exec >>$LOG`에서 죽어 **본체 미실행** → base의 EN-inflated 값이 v6 down보정 없이 노출 | ✅ 해결 |
| **만성** (6/15부터 드러남) | KO 실거래 앵커(DAANGN) 약화 — **DAANGN 수집 2026-05-19 사망**(총 476건) + recalc 계수가 최근 N일(`recalc_coefficients.py` **DAYS=60**) rolling window에서 `NAVER_CAFE`/`NAVER_CAFE_OLD`+`DAANGN`을 섞는데 DAANGN이 노화·이탈 → NAVER 오염값이 계수 지배 → 계수 인플레 → base EN 과선택 | ❌ **다음 사이클** |

> **⚠️ 주의 (과장 방지):** 6/15 "5장 부분실패"의 **직접 원인을 DAANGN 만료로 단정하지 않는다.** 6/15는 *최초 이상징후*일 뿐이고(base가 왜 5장만 썼는지의 직접 기술원인은 **미확정**), DAANGN 수집죽음·rolling-window·NAVER 오염은 그 *조사 과정에서 확정된 별개 만성 ROOT*다. (6/15 부분실패 → prevSource 기아 → 6/16 spike 연쇄는 관찰됐으나, 6/15 write가 5장에 그친 직접 원인 자체는 별도 미확정.)

**급성 원인 증거체인** (이전 세션 확정, `docs/PRICE_SYNC_POSTMORTEM_20260619.md` — 다음 세션이 필요시 재검증):
- syslog에 6/18 23:52 cron 호출은 있었음.
- 그런데 `v6_apply_20260618.log`에 23:52 `start` 줄이 **없음**.
- wrapper 순서 = `exec >>"$LOG"` → `echo start` → `docker exec v6_apply.py`. start조차 없음 = **exec redirect에서 죽음**(로직 ABORT 아님).
- 그날 로그가 `root:root 644`(낮 root 수동실행 흔적), cron은 `ubuntu`로 실행 → append 불가 → `set -e` 즉사.

**이번 세션 목표 = 모델 치료 아님.** ①23시 전 운영 동기화 정상화 ②frozen-v6 재실행되게 로그 풋건 제거 ③ja=1 P0 폭탄 제거 ④첫 live 관측. FROZEN_KOVALS 정리·JP-first base·en_coef 재캘리·DAANGN 수집 복구는 **다음 사이클**(아래 §다음 사이클).

---

## 이번 세션에 한 것 (전부 prod 라이브, 백업 있음)

1. **Un-freeze (base sync 재가동)**
   - `/opt/pokefolio/.env.prod` line88 `JAVA_TOOL_OPTIONS=-Dprice.sync.enabled=false` → 주석처리.
   - `sudo docker compose -f /opt/pokefolio/app/docker-compose.prod.yml up -d --no-deps --force-recreate back` (※ `--build` 안 씀 = 코드 드리프트 회피, env_file만 교체).
   - 검증: 부팅로그 `[PriceSync][FREEZE] price.sync.enabled=true`, 컨테이너 `JAVA_TOOL_OPTIONS` unset.
   - 백업: `/opt/pokefolio/.env.prod.bak_pre_unfreeze_20260619`.
2. **cron 4잡 주석해제** (ubuntu crontab): `crontab -l | sed 's/^#FREEZE20260619 //' | crontab -`
   - hold 23:50 / **v6 23:52** / sanity 23:55 / chart 23:57. base sync = Spring `@Scheduled` **23:45** (`PriceSyncScheduler.java:149`, host cron 아님).
3. **로그권한 풋건 하드닝** (6/18 mass 폭등 근본): `v6_apply_daily.sh` / `hold_outliers_daily.sh` / `sanity_cap_extreme_daily.sh`에
   `mkdir + sudo touch + sudo chown ubuntu:ubuntu + sudo chmod 664 + append-preflight(실패시 exit20)` 를 `exec >>$LOG` 직전 삽입.
   - 백업: `/opt/pokefolio/cron/*.bak_pre_chown_20260619`. 자가치유 실증됨(root로그→ubuntu 회복).
   - ko_chart는 로그 리다이렉트 없어 무수정.
4. **ja=1 MANUAL_ANCHOR P0 가드** (`v6_apply.py` line224):
   `if (jt and ja)` → `if (jt and ja and ja > 1)`
   - 이유: ja=1 앵커 2장(메가리자몽Y ex `CRD_25A858D0` av=934900 / 블래키 VMAX `CRD_A6F75029` av=685900)이 'JP없음 hold' 의도인데 ja=1이 truthy라, 밤 JP수집(23:00~30)으로 jt 생기면 `jt*av/1` 폭발 가능(+둘 다 sanity held=안 잡힘).
   - 효과: **오늘 0장 변경**(would-change 1059 불변, 20앵커 changed_today=N, 정상18장 JP추종 유지) + jt 생겨도 HOLD.
   - 백업: `/opt/pokefolio/scripts/v6_apply.py.bak_pre_anchorfix_20260619`.

검증 산출물(로컬): `~/Downloads/pokefolio_anchorfix_pre_/post_20260619/`, `pokefolio_price_sync_20260619_hardened/`, `price_jun10_18.csv`.

---

## 오늘밤 검증 (23:57 이후 1회)

```bash
KEY=~/pem/LightsailDefaultKey-ap-northeast-2.pem
ssh -i "$KEY" ubuntu@52.78.3.120 'bash -s' <<'EOF'
RUN_DATE=20260619       # ★날짜 고정: 00:00 넘겨 확인해도 6/19 밤 run을 봐야 함 ($(date)면 6/20 봄)
RUN_DATE_SQL=2026-06-19  # 동일 날짜 (SQL DATE 비교용)
echo "=== v6 로그 (start/COMMITTED/ABORT) ==="
tail -20 /opt/pokefolio/data/logs/v6_apply_${RUN_DATE}.log
echo "=== rollback table (오늘밤엔 *존재*가 정상=live 백업) ==="
docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -tA -c "SELECT to_regclass('public.ko_v6enbr_rollback_${RUN_DATE}');"
echo "=== latest KO 날짜 자동판정 (RUN_DATE_SQL과 같으면 PASS) ==="
docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -tA -c "
SELECT MAX(traded_at::date) AS latest_ko_date,
  CASE WHEN MAX(traded_at::date)=DATE '${RUN_DATE_SQL}' THEN 'PASS'
       ELSE 'STOP (날짜 불일치 = base 미실행/부분실패 의심)' END AS date_check
FROM price_snapshots WHERE source='KO_ESTIMATED';"
echo "=== 대표카드 + ja=1 2장 (traded_at 최신 batch 기준 — created_at 쓰지 말 것) ==="
docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c "
SELECT c.name,c.rarity_code,c.collection_number,ps.price ko,ps.chart_price FROM price_snapshots ps JOIN cards c ON c.card_id=ps.card_id
WHERE ps.source='KO_ESTIMATED' AND ps.traded_at::date=(SELECT MAX(traded_at::date) FROM price_snapshots WHERE source='KO_ESTIMATED')
AND c.card_id IN (  -- 대표 6장(card_id 고정) + ja=1 2장. name 조건 금지(동명 카드 다수)
  'CRD_BBF48E2A085C4050AA8B','CRD_7FEAB602A0214CDAB632','CRD_302EC9D2C71947778B51',
  'CRD_95962D36A0B54D96A10A','CRD_1589922DA5104539AFF5','CRD_8F6DB567A7EF4D5F9742',
  'CRD_25A858D01145493BB66AF82B8EA32B7C','CRD_A6F7502948814BF9A22C')
ORDER BY ko DESC;"
EOF
```

**통과(PASS) 기준:**
- v6 로그에 `start` + `COMMITTED <n>` 둘 다, `ABORT`/`sys.exit` 없음.
- `rollback_<오늘날짜>` **존재**(= live 백업 정상. 지금 NULL인 건 live 전이라 정상).
- 대표 6장 (card_id 고정, 기대값 ±10% 내. name 검색 금지=동명 다수):

  | 카드 | card_id | ~기대값 |
  |---|---|---|
  | 글레이시아 HR 20/40 | `CRD_BBF48E2A085C4050AA8B` | 10,300 |
  | 파이리 AR 168/165 | `CRD_7FEAB602A0214CDAB632` | 13,000 |
  | 꼬부기 AR 170/165 | `CRD_302EC9D2C71947778B51` | 16,300 |
  | 리자몽 GX SSR 209/150 | `CRD_95962D36A0B54D96A10A` | 392,200 (MANUAL_ANCHOR) |
  | 레쿠쟈 VMAX CSR 252/184 | `CRD_1589922DA5104539AFF5` | 75,200 |
  | 제크로무 ex BWR 174/086 | `CRD_8F6DB567A7EF4D5F9742` | 122,500 (FROZEN_KOVALS 정적값=거의 불변) |
- ja=1 2장: 메가리자몽Y ex **934900**, 블래키 VMAX **685900** HOLD 유지.
- chart_price는 price 대비 ±1.5%만.

> ※ **FROZEN_KOVALS 값 ≠ 실제가 (헷갈리지 말 것 / card_id 매핑은 DB 정·역방향 확정됨):** 제크로무 ex BWR는 FROZEN_KOVALS `(122500,7)`·**n=7≥3 → 적용**(latest=122500 일치, 거의 불변). 반면 파이리/꼬부기/레쿠쟈도 FROZEN_KOVALS에 `(2000,1)/(4500,1)/(95000,1)`로 등재돼 있으나 **n=1<3 → 미적용** (frozen rv는 v6 `line247: r10(rv) if hasdg(n>=3)` HIT 경로에서만 최종값이 됨). 이들 가격은 EN_BRIDGE/JP 경로로 결정 → **latest_ko(13046/16281/75180)가 정답**, frozen값(2000 등) 아님.

**STOP/롤백 기준:** v6 ABORT / 대표카드 폭등(글레이시아 6만↑ 등) / ja=1 2장 값 폭발 / rollback 미생성.

---

## 롤백 (문제 시, 전부 prod 백업으로 역순)

- **re-freeze:** `.env.prod` line88 주석 복원 + crontab 4줄에 `#FREEZE20260619 ` 재부착 + `docker compose -f /opt/pokefolio/app/docker-compose.prod.yml up -d --no-deps --force-recreate back`.
- **anchor 패치 롤백:** `sudo cp /opt/pokefolio/scripts/v6_apply.py.bak_pre_anchorfix_20260619 /opt/pokefolio/scripts/v6_apply.py` (cron이 파일 읽으므로 재빌드 불필요).
- **wrapper 하드닝 롤백:** `.bak_pre_chown_20260619` 복원.

---

## 철칙 (금지)

- `recalc_coefficients.py` 실행 금지 (DAYS=60 NAVER/DAANGN 오염 = 만성 원인).
- **낮에 v6 root 수동 LIVE 실행 금지** (같은날 `ko_v6enbr_rollback_YYYYMMDD` 생성 → 밤 v6 same-date ABORT + root 로그 풋건 재발).
- `FROZEN_KOVALS` 오늘 건드리지 말 것 (P0 아님, 정적 기술부채 — `project_frozen_kovals_techdebt_20260619`).
- `post_v6_spike_guard` 신규 cron 등록 금지.
- prod `git checkout/pull/reset/stash` 금지 (작업트리 dirty 핫픽스).
- postgres 재생성 금지 · `--no-deps` 없는 compose up 금지.

---

## 다음 사이클 (모델 치료 — 별도 새 세션, 외부 실거래 검증)

오늘 범위 아님. 운영복구가 아니라 모델 재수술.
- JP-first 소스선택 반전(현재 base의 EN 과선택 병), `en_coef` 0.34→~0.09 재캘리, EN graded 위생.
- `FROZEN_KOVALS` 절대값 하드코딩 → 검증된 실거래 anchor table + ratio/floor/hold 정책 분리.
- DAANGN 수집 복구(5/19 사망) + ground-truth 시드(raw·한국판·blind).
- 연계 메모리: `project_chase_pricing_model_status`, `project_price_root_coef_20260618`.

---

## 키 경로

| | |
|---|---|
| prod | `52.78.3.120` / key `~/pem/LightsailDefaultKey-ap-northeast-2.pem` (DB유저 `pokefolio`) |
| compose | `/opt/pokefolio/app/docker-compose.prod.yml` (env_file `/opt/pokefolio/.env.prod`) |
| 스크립트 | `/opt/pokefolio/scripts/v6_apply.py` · cron `/opt/pokefolio/cron/*_daily.sh` |
| DB | `docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db` |
| 진입 메모리 | `project_price_sync_logperm_footgun_20260619` (현재상태 헤드라인) |
