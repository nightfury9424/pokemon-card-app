# 글로벌 시세 파이프라인 — 설계 및 트러블슈팅

> 작성일: 2026-04-04

---

## 0. 비전

**한국 포켓몬 카드 시장의 시세 기준점을 만드는 플랫폼**

- 당근마켓처럼 C2C 거래 + TCGPlayer처럼 카드별 시세 그래프
- 한국 카드가 미국/일본 대비 얼마나 싼지 데이터로 보여줌
- 이 시세 데이터가 플랫폼 거래의 신뢰 기반이 됨
- 한국 포켓몬 카드 시장 시세를 우리 플랫폼이 정의하는 것이 목표

---

## 1. 핵심 원칙: 카드 동일성 보장

> **가장 중요한 것: 비교하는 카드가 진짜 같은 카드여야 한다**

같은 이름이어도 다른 카드일 수 있음:
- 리자몽 ex SSR (KO/JP 전용) ≠ 리자몽 ex SIR (EN에만 있음)
- 뮤 ex SSR art가 KO/JP와 EN이 다를 수 있음

### 동일성 판단 기준 (우선순위 순)

1. **컬렉션 번호 일치** (동시 출시 세트): 번호가 같으면 같은 카드
2. **일러스트레이터 일치**: 같은 그림 작가 = 같은 아트
3. **수동 검수**: 번호 다르거나 세트 다를 때 사람이 직접 확인

### 매핑 신뢰도 등급

| 등급 | 조건 | 처리 |
|------|------|------|
| ✅ CONFIRMED | 번호 일치 + 동시 출시 세트 | 자동 매핑 사용 |
| ⚠️ PROBABLE | 이름+레어리티 일치, 번호 다름 | 검수 후 사용 |
| ❌ MISMATCH | 아트/레어리티 다름 | 매핑 삭제, 미매핑 처리 |

---

## 2. 전체 파이프라인 구조

```
[데이터 수집 - 하루 1회 배치]

 KO 거래 데이터 (앱 내 실거래)
        ↓
 ┌──────────────────────────────────┐
 │        카드 매핑 레이어           │
 │  KO card_id → EN tcgplayer_id    │
 │  KO card_id → JP jp_card_id      │
 │  (동일 카드인지 검증됨)           │
 └──────────────────────────────────┘
        ↓              ↓              ↓
  EN 시세 수집      JP 시세 수집    KO 거래가
  (pokemontcg.io)  (야후옥션/메루카리)  (앱 DB)
        ↓              ↓              ↓
  USD 가격         JPY 가격         KRW 가격
        ↓              ↓
  × USD/KRW 환율   × JPY/KRW 환율
        ↓              ↓              ↓
 ┌──────────────────────────────────┐
 │       price_snapshots 테이블      │
 │  source: TCGPLAYER / YAHOO_JP /  │
 │          MERCARI_JP / APP / EBAY │
 └──────────────────────────────────┘
        ↓
 ┌──────────────────────────────────┐
 │         계수 계산                 │
 │  KO/EN 비율 = KO평균 / EN평균    │
 │  KO/JP 비율 = KO평균 / JP평균    │
 │  한미일 동시 존재시 3개 비율 모두 │
 └──────────────────────────────────┘
        ↓
 ┌──────────────────────────────────┐
 │      예상 가치 계산               │
 │  데이터 많은 시장 기준으로        │
 │  KO 카드 예상 가치 산출           │
 │  (EN or JP 중 샘플 많은 쪽 우선)  │
 └──────────────────────────────────┘
        ↓
    앱 그래프 / 시세 화면
```

---

## 3. 시세 소스별 수집 방법

### 3-1. EN — TCGPlayer (via pokemontcg.io)
- **API**: `https://api.pokemontcg.io/v2/cards/{id}`
- **데이터**: market price (USD), tcgplayer URL
- **주기**: 하루 1회
- **매핑**: `cards.tcgplayer_card_id` (이미 구현)
- **현황**: ✅ 구현 완료, 매핑 검수 진행 중

### 3-2. JP — 야후옥션 낙찰가
- **URL**: `https://auctions.yahoo.co.jp/search/search?p={검색어}&va={검색어}&auccat=&tab_ex=commerce&ei=utf-8&aq=-1&oq=&sc_i=&exflg=1&b=1&n=50&s1=end&o1=d&mode=2`
- **검색어**: `{JP카드명} {등급코드} {번호}/{총수}` (예: `リザードンex SSR 331/190`)
- **수집 대상**: 낙찰완료 리스트 (sold listings)
- **데이터**: 낙찰가(JPY), 낙찰일
- **주기**: 하루 1회, 최근 7일치
- **source**: `YAHOO_JP`

### 3-3. JP — 메루카리
- **URL**: `https://jp.mercari.com/search?keyword={검색어}&status=sold_out`
- **수집 대상**: 판매완료 상품
- **데이터**: 판매가(JPY), 판매일
- **source**: `MERCARI_JP`

### 3-4. 그레이딩 카드 — eBay
- **URL**: `https://www.ebay.com/sch/i.html?_nkw={검색어}+PSA+10&LH_Sold=1&LH_Complete=1`
- **검색어**: `{EN카드명} {세트명} PSA 10` (등급별로 검색)
- **수집 대상**: 낙찰완료 (Sold listings)
- **데이터**: 낙찰가(USD), 등급(PSA10/PSA9/BRG등)
- **source**: `EBAY`
- **매핑**: `cards.tcgplayer_card_id` 있으면 자동 연결

### 3-5. 환율
- **소스**: 환율 API (ExchangeRate-API or 한국은행 OpenAPI)
- **종류**: USD/KRW, JPY/KRW
- **주기**: 하루 1회
- **저장**: 기존 환율 테이블에 JPY 추가

---

## 4. 예상 가치 산출 로직

```
카드별 예상 KO 가치 계산:

1. EN 데이터 있고 샘플 충분 (30일간 스냅샷 10개 이상):
   → predicted_KO = EN_avg_KRW × KO/EN_coefficient

2. JP 데이터 있고 샘플 충분 (30일간 낙찰 5건 이상):
   → predicted_KO = JP_avg_KRW × KO/JP_coefficient

3. 둘 다 있으면:
   → 데이터 많은 쪽 우선, 혹은 가중평균

4. 둘 다 없으면:
   → KO 거래 히스토리 평균만 표시
```

---

## 5. DB 마이그레이션

### 5-1. 추가할 컬럼 — cards 테이블

```sql
-- JP 카드 매핑
ALTER TABLE cards ADD COLUMN jp_card_name  VARCHAR(200);  -- 야후옥션 검색용 JP명
ALTER TABLE cards ADD COLUMN jp_set_id     VARCHAR(50);   -- JP 세트 코드 (sv4e 등)
ALTER TABLE cards ADD COLUMN jp_number     VARCHAR(20);   -- JP 카드 번호

-- 예상 가치
ALTER TABLE cards ADD COLUMN predicted_price_krw   INTEGER;     -- 예상 한국 가치(KRW)
ALTER TABLE cards ADD COLUMN predicted_price_source VARCHAR(20); -- 근거 소스 (EN/JP/BOTH)
ALTER TABLE cards ADD COLUMN predicted_updated_at  TIMESTAMP;   -- 마지막 계산 시각
```

### 5-2. 신규 테이블 — jp_set_mappings

```sql
CREATE TABLE jp_set_mappings (
    product_id  VARCHAR(50) PRIMARY KEY,  -- KO product_id
    jp_set_id   VARCHAR(50) NOT NULL,     -- JP 세트 코드
    jp_set_name VARCHAR(200),             -- JP 세트명 (야후옥션 검색용)
    created_at  TIMESTAMP DEFAULT NOW()
);
```

### 5-3. price_snapshots source 종류 확장

```
기존: 'APP', 'TCGPLAYER'
추가: 'YAHOO_JP', 'MERCARI_JP', 'EBAY'
(스키마 변경 없음 — source는 VARCHAR)
```

### 5-4. 환율 테이블 JPY 추가

기존 exchange_rates 테이블 또는 ExchangeRateClient에 JPY/KRW 추가

---

## 6. 역사 데이터 (그래프 소급 적용)

- **KO**: ICU 6,698건 + Naver Shopping 29,632건 이미 DB에 있음 → 그래프 즉시 가능
- **EN**: pokemontcg.io market price는 현재가만 줌, 과거 데이터 없음
  → 매일 스냅샷 수집 시작한 날부터 그래프 생성
- **JP**: 야후옥션은 과거 낙찰가 조회 가능 (최대 1년 치)
  → 초기 수집 시 과거 데이터 한 번 bulk 수집

---

## 7. 작업 순서 (Phase별)

### Phase 1: 현재 매핑 마무리 ✅
- [x] SWSH/SM/XY/BW ptcg_set_mappings 등록 (122개 세트)
- [x] jp_set_mappings 등록 (118개 세트)
- [x] scrydex_slug 생성 (2,119장 중 1,993장, 94.1%)
- [x] scrydex_scraper.py 실행 중 (JP+EN 동시 수집, 백그라운드)

### Phase 2: DB 마이그레이션 ✅
- [x] jp_set_mappings 테이블 생성 및 데이터 등록
- [x] cards.scrydex_slug 컬럼 추가
- [ ] predicted_price 컬럼 추가 (Phase 5에서)

### Phase 3: JP 매핑 ✅
- [x] KO collection_number = JP number 규칙 확인
- [x] scrydex에서 JP/EN 동시 수집으로 대체

### Phase 4: 시세 수집 🔄
- [x] scrydex_scraper.py — JP+EN+eBay 통합 수집 (백그라운드 실행 중)
- [ ] Spring Boot 일간 배치 스케줄러 (추후)

### Phase 4-후속: 계수 재계산
- [ ] scraper 완료 후 GET /api/prices/coefficient 호출

### Phase 5: 예상 가치 계산 배치
- [ ] KO/EN 계수, KO/JP 계수 자동 계산
- [ ] 카드별 predicted_price_krw 업데이트

### Phase 6: 그래프 UI
- [ ] 카드 상세 — KO/EN/JP 3개 라인 차트
- [ ] 7일/30일 전환
- [ ] 계수/예상 가치 표시

---

## 8. 트러블슈팅 이력

### TS-001: pokemontcg.io API rate limit 소진
- **현상**: 1,000건/일 제한, 매핑 도중 429 에러
- **해결**: pokemon-tcg-data GitHub 레포 로컬 클론 → 무제한 사용

### TS-002: KO SSR ≠ EN SIR (레어리티 오매핑)
- **현상**: 샤이니 세트 SSR이 EN SIR로 매핑됨
- **해결**: SSR → {Shiny Ultra Rare, SIR, Hyper Rare}로 RARITY_MAP 수정

### TS-003: KO/JP 전용 카드 (EN 없음)
- **현상**: 리자몽 ex SSR (331/190) — EN Paldean Fates에 Shiny Ultra Rare 없음
- **결론**: EN 매핑 불가, JP 매핑 필요

### TS-004: ptcg_set_mappings 1,486장 누락
- **현상**: SWSH/SM/XY/BW 세트 미등록 → 전체 카드 매핑 시도 불가
- **해결 예정**: 세트 매핑 수동 추가

### TS-005: 검수 UI CORS 오류
- **현상**: file:// HTML → POST localhost:8080 불가
- **해결 예정**: 파이썬 로컬 서버(python3 -m http.server)로 HTML 제공

### TS-006: sv5 오매핑
- **현상**: KO ENHANCED_BOOSTER → sv5 (Temporal Forces) 매핑, 카드 풀 불일치
- **해결 예정**: 정확한 EN set ID 확인 후 재매핑
