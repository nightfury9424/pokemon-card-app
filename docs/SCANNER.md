# 스캐너 v2 — DINOv2 + FAISS

## 현재 상태 (2026-05-01)

| 항목 | 내용 |
|------|------|
| FAISS DB | 7,192 벡터, 3,491 카드 종류 |
| 이미지 | EN/JP/KO ~10,237장 (`scanner/data/cards/`) |
| FastAPI | port 8082, 정상 동작 |
| Spring Boot | `ScannerController` → `http://localhost:8082/identify` |
| Flutter | `imageStream` 실시간 스캔 (`scanner_screen.dart`) |

---

## 파이프라인

```
카메라 프레임 (BGRA8888, iOS)
→ Isolate: BGRA→JPEG 변환
→ POST /api/scanner/identify  (Spring Boot :8080)
→ POST http://localhost:8082/identify  (FastAPI)
→ OpenCV 카드 영역 감지
→ DINOv2 CLS 토큰 임베딩 (768-dim, L2 정규화)
→ FAISS IndexFlatIP Top-10 검색
→ card_id별 최고 점수 집계 → Top-5 반환
→ Flutter 결과 바텀시트
```

---

## 스코어 임계값

| score | status |
|-------|--------|
| ≥ 0.70 | `success` — 즉시 확정 |
| 0.48 ~ 0.70 | `low_confidence` — 후보 제시 |
| < 0.48 | `not_found` |

---

## 서버 실행

```bash
cd scanner
KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/uvicorn main:app \
  --host 0.0.0.0 --port 8082
```

> macOS에서 OpenMP 스레드가 uvicorn 프로세스와 충돌 → OMP_NUM_THREADS=1 필수

---

## 프로젝트 구조

```
scanner/
├── data/
│   ├── cards/              # EN/JP/KO 이미지 (~10,237장)
│   ├── scrydex_refs.csv
│   └── download_scrydex.py
├── db/
│   ├── build_db.py         # FAISS DB 구축 스크립트
│   ├── card_db.faiss       # 벡터 DB (7,192 벡터)
│   └── card_meta.json      # card_id 메타 (3,491종)
└── main.py                 # FastAPI (port 8082)
```

---

## FAISS DB 재구축

카드 추가/변경 시:
```bash
conda activate scanner_v2
cd scanner/db
python build_db.py
# PostgreSQL에서 KO 카드 조회 → JP/EN/KO 이미지 임베딩 → card_db.faiss + card_meta.json
```

---

## conda 환경 (scanner_v2)

```bash
conda create -n scanner_v2 python=3.11
conda activate scanner_v2
pip install torch torchvision transformers faiss-cpu opencv-python pillow \
            fastapi uvicorn python-multipart tqdm psycopg2-binary
```

---

## 개발 단계

| 단계 | 내용 | 상태 |
|------|------|------|
| 1 | 이미지 수집 (EN/JP scrydex) | ✅ |
| 2 | FAISS DB 구축 (`build_db.py`) | ✅ |
| 3 | FastAPI 서버 (`main.py`) | ✅ |
| 4 | Spring Boot 연동 | ✅ |
| 5 | Flutter 실시간 스캔 UI | ✅ |
| 6 | 번개/당근 실사 이미지 크롤링 + DINOv2 파인튜닝 | 🔲 |

---

## 향후: 2단계 (파인튜닝)

번개장터/당근마켓 체결 완료 게시글에서:
- 이미지 → `scanner/data/realshots/{card_id}/` 저장
- 가격 + 날짜 → `price_snapshots` INSERT
- 같은 card_id 이미지들을 positive pair로 NT-Xent 학습

→ [PRICE.md](PRICE.md) 참고
