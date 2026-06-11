# 스캐너 v2 — DINOv2 + FAISS

## 현재 상태 (2026-06-11)

| 항목 | 내용 |
|------|------|
| FAISS DB | **~58,323 벡터, ~4,221 카드 종류** (5/6 베이스 58,260/4,158 + 6/11 누락 63장 증분) |
| 임베딩 | DINOv2-base **finetuned** → CLS + patch_mean concat **1536-dim**, L2 정규화 |
| 이미지 | EN/JP/KO ~15,559장 (`scanner/data/cards/`) |
| FastAPI | port 8082, `/identify` (warp→임베딩→FAISS top-20→card_id 집계) |
| Spring Boot | `ScannerController` → `http://localhost:8082/identify` |
| Flutter | `imageStream` 실시간 스캔 (`scanner_screen.dart`) |
| 모델 | `scanner/model/dinov2_finetuned` (없으면 `facebook/dinov2-base` 폴백) |

> ⚠️ 5/18 이전 문서는 "7,192벡터 / 768-dim CLS" 였으나 **stale** — 현재는 위 표 기준.

---

## 파이프라인

```
카메라 프레임 (BGRA8888, iOS)
→ Isolate: BGRA→JPEG
→ POST /api/scanner/identify  (Spring Boot :8080)
→ POST http://localhost:8082/identify  (FastAPI)
→ CardDetector.find_and_warp_card  (카드 영역 감지 + 원근 보정)
→ DINOv2 임베딩 = [CLS ‖ patch_mean] 1536-dim, L2 정규화
→ FAISS IndexFlatIP top-20 검색
→ card_id별 최고 점수 집계 → top-5 반환
→ Flutter 결과 바텀시트
```

## 스코어 임계값

| score | status |
|-------|--------|
| ≥ 0.70 | `success` — 즉시 확정 |
| 0.48 ~ 0.70 | `low_confidence` — 후보 제시 |
| < 0.48 | `not_found` |

---

## 임베딩/증강 방식 (★핵심 — build_db.py / build_missing.py 공통)

카드 1장당 **이미지(jp/en/ko/official) × 증강 5종**을 임베딩 → 그래서 카드당 ~10–15벡터.

- **이미지 소스** (`find_images`): `data/cards/{cardId}_jp.png`, `_en.png`, `_ko.png`, `{officialCode}.jpg`
- **전처리** (`preprocess`): `cv2.imread` → `CardDetector.find_and_warp_card` (warp 정규화, 실패 시 원본)
- **증강** (`augment`) — 카탈로그 1장 → **5장**:
  1. 원본
  2. 밝게 `convertScaleAbs(beta=+55)`
  3. 어둡게 `convertScaleAbs(beta=-55)`
  4. 회전 `+7°`
  5. 회전 `-7°`
- **임베딩** (`embed_bgr`): `CLS ‖ patch_mean` concat(1536) → L2 정규화 → `IndexFlatIP.add`

> 이 5종 증강 + warp 가 조명/각도/홀로 글레어 robustness 의 핵심. **단일 카탈로그 벡터(증강 없음)는 robustness 떨어짐 → 쓰지 말 것.**

---

## A) 전체 재구축 — `scanner/db/build_db.py`

PostgreSQL 전체 KO 카드 → 이미지 임베딩 → 인덱스 새로 생성. **~4,000장 × ~14벡터 = 약 5시간.**

```bash
KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/python scanner/db/build_db.py
# DB(nightfury@localhost) KO 카드 → card_db.faiss + card_meta.json 전부 새로
```

→ 카드 몇 장 추가하려고 5시간 돌리는 건 낭비. 보통 **B) 증분**을 쓴다.

## B) 증분 추가 (신규 카탈로그 카드) — `scanner/db/build_missing.py` ★

인덱스에 **없는 visible 카드만** 골라 기존 인덱스에 append. 같은 증강 방식. **63장이면 ~몇 분.**

> ⚠️ **인덱스는 DB에 새 카드가 들어가도 자동 갱신 안 됨.** `train_agent.py`(맥북 재학습 agent)는 **유저 스캔 캡처**만 증분 추가하지 신규 카탈로그 카드는 안 넣음. → 신규 카드 추가 후엔 **주기적으로 build_missing 으로 catch-up** 필요. (2026-06-11 기준 5/6 이후 누락 63장 = 닌자스피너 27 + 이브이계열 hit 3 + 피카츄 프로모 등)

절차:
```bash
# 1) 누락 카드 산출 (DB visible 카드 − meta.cards)
ssh ...prod... "docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -t -A -F '|' \
  -c \"SELECT card_id,is_visible,COALESCE(jp_scrydex_ref,''),COALESCE(en_scrydex_ref,''),COALESCE(rarity_code,''),COALESCE(official_card_code,''),name FROM cards;\"" > /tmp/db_cards_full.txt
python3 -c "import json; meta=set(json.load(open('scanner/db/card_meta.json'))['cards']); \
  rows=[l.split('|',6) for l in open('/tmp/db_cards_full.txt').read().splitlines() if l.strip()]; \
  miss=[{'cardId':r[0],'jpRef':r[2],'enRef':r[3],'name':r[6],'rarity':r[4],'officialCode':r[5]} \
        for r in rows if len(r)==7 and r[1] in ('t','true') and r[0] not in meta and (r[2] or r[3])]; \
  json.dump(miss,open('/tmp/missing_cards.json','w'),ensure_ascii=False); print(len(miss))"

# 2) 증분 임베딩 (jp/en 이미지 없으면 scrydex CDN 다운로드 → data/cards/, warp + 증강5 + 임베딩)
KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/python scanner/db/build_missing.py
# 시작점 = .bak_pre_add63 (깨끗한 prod-동일 백업) → 63장 add → card_db.faiss + card_meta.json
```

- 백업: `card_db.faiss.bak_pre_add63` / `card_meta.json.bak_pre_add63` (= 직전 prod 인덱스 = 롤백용)
- ⚠️ 한 번 1벡터(warp·증강 없이)로 잘못 add 했던 적 있음 → build_missing 은 **항상 .bak 에서 시작**해 오염 방지.

---

## C) prod 스캐너 배포 (hot-swap) ★

prod 스캐너(`pokefolio-scanner` 컨테이너)는 `/app/scanner/db/card_db.faiss` + `card_meta.json` 을 로컬에서 로드. → 맥에서 만든 새 인덱스를 **그대로 교체 + 재시작.**

> ⚠️ **심사(App Review) 대기 중엔 배포 금지.** 컨테이너 재시작 = 스캔 잠깐 다운 + prod 변경. **승인 후** 진행. (feedback: prod 직접수정 = 백업+diff+롤백+명시 OK 후)

```bash
# 1) prod 현재 인덱스 백업 (롤백용)
ssh ...prod... "docker exec pokefolio-scanner sh -c 'cp /app/scanner/db/card_db.faiss /app/scanner/db/card_db.faiss.bak_$(date +%Y%m%d) && cp /app/scanner/db/card_meta.json /app/scanner/db/card_meta.json.bak_$(date +%Y%m%d)'"

# 2) 새 인덱스 전송 (맥 → Lightsail 호스트, faiss ~342MB)
scp -i ~/pem/LightsailDefaultKey-ap-northeast-2.pem \
  scanner/db/card_db.faiss scanner/db/card_meta.json ubuntu@52.78.3.120:/tmp/

# 3) 컨테이너에 복사 + 재시작 (원자 reload)
ssh ...prod... "docker cp /tmp/card_db.faiss pokefolio-scanner:/app/scanner/db/card_db.faiss && \
  docker cp /tmp/card_meta.json pokefolio-scanner:/app/scanner/db/card_meta.json && \
  docker restart pokefolio-scanner"

# 4) 검증 — 헬스 + ntotal 증가 + 새 카드 인식
ssh ...prod... "docker exec pokefolio-scanner python3 -c \"import faiss,json; \
  print('ntotal', faiss.read_index('/app/scanner/db/card_db.faiss').ntotal, \
  'cards', len(json.load(open('/app/scanner/db/card_meta.json'))['cards']))\""
```

> 대안(자동): `train_agent.py` 의 deploy 경로 = staging 인덱스를 S3 presigned-URL 로 올리고 백엔드 `/api/scanner-agent/...` 가 forward → 스캐너 원자 reload. 수동 hot-swap 이 더 단순/확실.

---

## conda 환경 (scanner_v2)

```bash
conda create -n scanner_v2 python=3.11 && conda activate scanner_v2
pip install torch torchvision transformers faiss-cpu opencv-python pillow \
            fastapi uvicorn python-multipart tqdm psycopg2-binary requests boto3
```

## 서버 실행

```bash
cd scanner
KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/uvicorn main:app --host 0.0.0.0 --port 8082
```
> macOS OpenMP 충돌 → `OMP_NUM_THREADS=1` 필수.

---

## 프로젝트 구조

```
scanner/
├── app/detector.py          # CardDetector (카드 감지 + warp)
├── data/
│   ├── cards/               # EN/JP/KO 카탈로그 이미지 (~15,559장)
│   └── realshots/           # 실사진 (파인튜닝용)
├── db/
│   ├── build_db.py          # A) 전체 재구축 (~5시간)
│   ├── build_missing.py     # B) 신규 카드 증분 추가 (~분) ★
│   ├── card_db.faiss        # 벡터 DB
│   ├── card_meta.json       # {vectors:[card_id…], cards:{card_id:{name,rarity,officialCode,scrydexRef}}}
│   └── *.bak_pre_add63      # 롤백 백업
├── train_agent.py           # 유저 스캔 캡처 증분 + S3 staging deploy (카탈로그 X)
├── finetune.py              # DINOv2 contrastive 파인튜닝 (NT-Xent, realshots)
└── main.py                  # FastAPI (port 8082, /identify)
```

---

## 변경 로그

- **2026-06-11**: 5/6 이후 인덱스 누락 visible 63장 catch-up (`build_missing.py` 신규). 닌자스피너 27 + 테라스탈페스타 이브이계열 hit(부스터/쥬피썬더/타부자고) + 피카츄 프로모 등. **로컬 staging 완료, prod 배포는 심사 승인 후.**
- 5/6: 베이스 인덱스 58,260벡터 / 4,158카드.

## 향후: 파인튜닝 (2단계)

번개/당근 체결 게시글 실사진 → `data/realshots/{card_id}/` → 같은 card_id positive pair NT-Xent 학습 (`finetune.py`). → [PRICE.md](PRICE.md) 참고.

## 실사진 추가 학습 (2026-06-11~)
홀로 SAR 등 공식 평면 스캔만으론 인식 약한 카드 → 유저 실사진 추가로 보강.
- **도구**: `scanner/db/add_booster.py` (build_missing.py 함수 재사용: preprocess(warp) / augment(원본+밝기2+회전2=5) / embed_bgr(DINOv2 CLS+patch_mean 1536 L2)).
- **흐름**: 실사진 N장 × 5증강 임베딩 → 기존 `card_db.faiss`+`card_meta.json` 로드 → 해당 cardId로 `index.add()` + `meta["vectors"].append(cardId)` → 저장. crop은 `booster_crops/`에 저장(warp 검증: ar≈1.40 정상 / 1.00=느슨하지만 카드아트 지배적이면 OK·additive라 오매칭위험 낮음).
- **배포(hot-swap)**: `rsync -az --rsync-path="sudo -n rsync" card_db.faiss card_meta.json → ubuntu@52.78.3.120:/opt/pokefolio/data/faiss/` (bind-mount→컨테이너 `/app/scanner/db`) → `docker restart pokefolio-scanner` (reload ~1분, 로그 "준비 완료 — 벡터 N개" 확인). 백업 `.bak_pre_booster`(로컬+prod).
- **사례**: 부스터 ex SAR(`CRD_3935851BE6988D5F34B3`) 10→35벡 (KO2+JP2+인니1 ×5). 다른 약인식 카드도 동일 패턴 재사용.
