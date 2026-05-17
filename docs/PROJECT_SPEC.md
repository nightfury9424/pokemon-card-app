# 포켓몬 카드 앱 — 전체 프로젝트 스펙

> 마지막 업데이트: 2026-05-03

---

## 서비스 개요

포켓몬 카드 자산 관리 + 시세 조회 + AI 스캐너 + 거래 플랫폼 앱.  
번개장터 실거래 데이터를 수집해 KO 예상가를 계산하고, DINOv2 기반 카드 인식 스캐너로 카드를 자동 식별한다.

---

## 아키텍처

```
포켓몬 카드 앱
├── back/      Spring Boot 4.0.4 · Java 20          port 8080
├── front/     Flutter 3.41.4 · iOS                  
├── grading/   FastAPI · PyTorch                     port 8081
└── scanner/   FastAPI · DINOv2 + FAISS              port 8082
```

### 기술 스택

| 레이어 | 기술 |
|--------|------|
| 백엔드 | Spring Boot 4.0.4, Java 20, JPA, PostgreSQL |
| 앱 | Flutter 3.41.4, go_router, iOS |
| 스캐너 | FastAPI, DINOv2-base (파인튜닝), FAISS IndexFlatIP |
| 그레이딩 | FastAPI, PyTorch |
| DB | PostgreSQL, `nightfury` 유저, `pokemon_card_db` |

---

## DB 현황

**총 DB 용량: 156MB**

| 테이블 | 행 수 | 용량 | 설명 |
|--------|--------|------|------|
| cards | 4,097 | 103MB | KO 고레어 카드 (C/U/R 삭제됨) |
| price_snapshots | 149,841 | 43MB | 실거래 시세 스냅샷 |
| products | 476 | 200kB | 번개장터 상품 |
| assets | 0 | - | 유저 보유 카드 |
| trade_posts | 0 | - | 판매글 (개발 중) |
| sale_listings | 0 | - | 판매 목록 (개발 중) |
| users | 0 | - | 유저 (개발 중) |

### 카드 등급별 분포 (KO 4,097장)

| 등급 | 수량 | 등급 | 수량 |
|------|------|------|------|
| RR | 1,206 | HR | 183 |
| SR | 995 | UR | 130 |
| AR | 496 | PR | 126 |
| S | 263 | RRR | 115 |
| SAR | 221 | SSR | 72 |
| CSR | 40 | CHR | 54 |
| ACE | 31 | BWR | 2 |

### 시세 데이터 출처 (149,841건)

| 출처 | 건수 | 기간 |
|------|------|------|
| EBAY | 55,475 | 2023~2026 |
| SCRYDEX_EN | 30,966 | 2026-03~04 |
| NAVER_SHOPPING | 29,556 | 2026-03 |
| SCRYDEX_JP | 25,263 | 2026-03~04 |
| ICU | 6,685 | 2022~2026 |
| TCGPLAYER | 1,352 | 2026-04 |
| BUNJANG | 544 | 2026-05~ |

---

## 파일 시스템 용량

**총 프로젝트: 16GB**

| 경로 | 용량 | 내용 |
|------|------|------|
| scanner/ | 15GB | 전체 스캐너 |
| └ data/cards/ | 9.4GB | 카드 레퍼런스 이미지 15,397장 (JP/EN/KO) |
| └ data/crawl_raw/images/ | 4.6GB | 번개장터 크롤 사진 12,288장 |
| └ data/realshots/ | 163MB | 라벨링된 학습용 실사 410장 (229 카드종) |
| └ model/ | 336MB | DINOv2 파인튜닝 모델 |
| └ db/ | 22MB | FAISS 인덱스 + 메타 |
| front/ | 759MB | Flutter 앱 |
| grading/ | 183MB | 그레이딩 서비스 |
| back/ | 2.1MB | Spring Boot |

---

## 주요 API 엔드포인트 (총 47개)

### 백엔드 (Spring Boot :8080)

**카드**
- `GET /api/cards/market` — 고레어 카드 시세 목록 (홈 HOT 섹션)
- `GET /api/cards/{cardId}` — 카드 상세
- `GET /api/cards/search` — 카드 검색

**시세**
- `GET /api/prices/cards/{cardId}/history` — 카드 시세 이력
- `GET /api/prices/cards/{cardId}/ko-price` — KO 예상가 계산
- `GET /api/prices/coefficient` — EN/JP → KO 환율 계수
- `GET /api/prices/cards/{cardId}/scrydex-live` — scrydex 실시간 시세

**자산**
- `GET /api/assets` — 내 카드 목록
- `GET /api/assets/portfolio` — 포트폴리오 요약

**거래** (개발 중)
- `GET/POST /api/trades` — 거래글 목록/등록
- `GET /api/trades/cards/summary` — 카드별 판매 요약
- `PUT /api/trades/{tradeId}/status` — 상태 변경

**어드민**
- `POST /api/admin/fetch-global-prices` — 전체 시세 수집
- `POST /api/admin/map-cards` — scrydex 카드 매핑

**기타**
- `GET /api/users/me` — 내 정보
- `POST /api/auth/kakao/token` — 카카오 로그인
- `GET /api/chat/rooms` — 채팅방 목록

### 스캐너 (FastAPI :8082)

- `POST /identify` — 카드 사진 → DINOv2 FAISS 인식
- `GET /scrydex/search` — scrydex 카드 검색
- `POST /scrydex/save` — JP/EN ref 저장 + 이미지 다운로드
- `GET /scrydex/unmapped` — 미매핑 카드 목록
- `GET /scrydex/ai_search` — AI 유사 카드 검색
- `DELETE /cards/{cardId}` — 카드 삭제

---

## 스캐너 ML 파이프라인

```
번개장터 크롤 → label.html 라벨링 → training_data.json 축적
    → finetune.py (NT-Xent SimCLR) → build_db.py (FAISS 재빌드)
    → 서버 재시작
```

| 항목 | 현황 |
|------|------|
| 임베딩 방식 | CLS + patch-mean concat (1536-dim) |
| 모델 | DINOv2-base 파인튜닝 (last 2 blocks) |
| FAISS 인덱스 | IndexFlatIP(1536) — 재빌드 중 |
| 학습 데이터 | training_data.json 846건 |
| 레퍼런스 이미지 | 15,397장 (4,097 카드 × JP/EN/KO) |
| 실사 학습 이미지 | 410장 (229 카드종) |
| crawl 대기열 | crawl_results_2.json 4,697건 |

---

## 개발 현황

| 기능 | 상태 |
|------|------|
| 카드 DB (KO 고레어) | ✅ 완료 (4,097장) |
| scrydex JP/EN 매핑 | ✅ 완료 |
| 시세 수집 (EBAY/scrydex/네이버) | ✅ 완료 |
| AI 카드 스캐너 | ✅ 운영 중 (업그레이드 중) |
| 등급 평가 (그레이딩) | ✅ 운영 중 |
| 자산 관리 | ✅ 운영 중 |
| 번개장터 가격 파이프라인 | 🔄 진행 중 (라벨링 4,697건 대기) |
| 판매/거래 기능 | 🔜 개발 예정 |
| 유저 인증 (카카오) | 🔜 개발 예정 |
