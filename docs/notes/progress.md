# 포켓몬 카드 앱 — 개발 현황

> 마지막 업데이트: 2026-04-08

---

## 스택

| 구분 | 기술 |
|------|------|
| 백엔드 | Spring Boot (Java 17), PostgreSQL, port 8080 |
| 프론트 | Flutter, go_router, fl_chart |
| 인증 | Kakao OAuth2 + JWT |
| DB 마이그레이션 | ddl-auto: validate (새 테이블은 수동 DDL) |

---

## 완료된 기능

### 인프라
- Kakao OAuth2 로그인 + JWT 인증
- 카드 마스터 DB: 17,932개 (KO 기준), 등급 BWR 포함

### 자산 관리
- 자산 CRUD + 포트폴리오 (시세 기반 평가액)
- 컬렉션 볼 뱃지 (고레어 수 기반): 몬스터볼/슈퍼볼/하이퍼볼/마스터볼

### 거래
- 거래글 CRUD + 사진 업로드
- 관심(찜) 토글 + 관심 목록 화면
- 거래글 필터 (sellerId 등)

### UI (토스증권 스타일)
- 홈: 총 평가 자산 크게 + 카드 리스트
- 자산 정렬 (등급/가격/이름/수량)
- 레어도 글로우 통일, 가격 콤마 포맷

### 시세 파이프라인 (2026-04-05 완성)
- **3개 시장 시세 수집**: KO(앱 거래) / JP(Scrydex) / EN(Scrydex + TCGPlayer)
- **scrydex_scraper.py**: JP+EN RAW 히스토리 전체 + eBay 실거래가 수집
- **slug 생성**: KO 고레어 slug 자동 생성 (HR/ACE/RR/RRR/PR/H/SV-P 포함)
- **한국 예상 가치 계수**: ~0.515 (KO가 해외 대비 약 48% 저렴)
- **매일 새벽 3시 자동 동기화**: `PriceSyncScheduler.java` `@Scheduled` + `--incremental` (당일 수집 카드 스킵)

### 프론트 시세 화면 (2026-04-05 완성)
- **3라인 차트**: KO(초록) / JP(파랑) / EN(주황) fl_chart LineChart, 공통 시간축
- **"한국 예상 가치"** 라벨 + `?` 버튼 → 다이얼로그 (한/일/미 3개 시장 기반 설명)
- 기간 토글 (7d / 30d)
- % 변동 표시 (데이터 있을 때만)

### 채팅 (2026-04-06 완성)
- Spring WebSocket STOMP + Flutter web_socket_channel
- chat_room_screen.dart, 거래 상세 → 채팅방 연결, `/chat/:roomId` 라우팅

### 고레어 카드 확장 + 이미지 대체 (2026-04-07~08)
- **HIGH_RARE_CODES 확장**: SSR/SAR/BWR/CSR/CHR/UR/SR/AR + HR/ACE/RR/RRR/PR/H + SV-P 프로모
- **고레어 총계**: 3,562장 (기존 ~2,119장에서 대폭 확장)
- **한국 이미지 저작권 대응**: pokemonkorea.co.kr 이미지 사용 불가 통보 수신
- **이미지 대체**: scrydex EN/JP 이미지로 교체
  - EN (scrydex): 1,719장 → `images.scrydex.com/pokemon/{tcgplayer_card_id}/medium`
  - JP (scrydex): 1,250장 → `images.scrydex.com/pokemon/{jp_set_id}-{number}/medium`
  - 미매핑(MEGA/BW): 593장 → 카드 뒷면 + "이미지 없음" 안내
- **CardImage 공통 위젯** (`lib/core/widgets/card_image.dart`): pokemonkorea URL 자동 차단
- **카드 속성 크롤링** (`/tmp/crawl_card_attrs.py`): pokemoncard.co.kr → HP/card_type/rarity_code
  - HP 수집: 2,452/3,562장 완료
  - card_type 수집: 3,005/3,562장 완료
  - 신규 컬럼: `cards.hp INTEGER`, `cards.card_type VARCHAR(30)`
- **EN 카드 매핑**: 1,719장 완료 (`/tmp/map_en_cards.py`)

---

## 시세 파이프라인 상세

### price_snapshots source 종류
| source | 내용 |
|--------|------|
| APP | 앱 내 거래 (KO RAW) |
| SCRYDEX_JP | scrydex JP 시세 히스토리 |
| SCRYDEX_EN | scrydex EN 시세 히스토리 |
| EBAY | scrydex 경유 eBay 실거래가 |
| TCGPLAYER | pokemontcg.io TCGPlayer 가격 (레거시) |

### 스크래퍼 파일
- `/tmp/scrydex_scraper.py` — 메인 (JP+EN 전체 히스토리 + eBay)
  - `--incremental`: 오늘 이미 수집한 카드 스킵 (일배치용)
- `/tmp/ebay_scraper.py` — MEGA/BW 전용 eBay 직접 스크랩 (eBay 차단, API 필요)
- `/tmp/generate_slugs.py` — KO 카드명 → scrydex slug 생성

### 커버리지 갭
| 구분 | 장수 | 원인 | 해결 방법 |
|------|------|------|----------|
| slug 없음 (KO 독자 발매) | 126장 | MEGA 세트 등 해외 미출시 | eBay Finding API |
| BW 구버전 | 243장 | scrydex 미커버 | eBay Finding API |

### 한국 예상 가치 계수
- 검증된 세트 한정 (`VERIFIED_SET_IDS = ["sv3pt5"]` — 포켓몬 카드 151)
- 계산: 한국 평균가 / 해외 평균가(KRW 환산) 중앙값
- 이상치 제거: 비율 0.01~5.0 범위만

### 주요 DB 테이블
- `price_snapshots` — 시세 스냅샷 전체
- `ptcg_set_mappings` — KO product_id → pokemontcg.io set_id
- `jp_set_mappings` — ptcg_set_id → scrydex JP set_id (예: sv7a_ja)

---

## 수익화 모델

- **월 $5 자발적 후원** (기능 제한 없음, 앱스토어 인앱결제 or 외부)
- 후원자 혜택: 블루 배지(인스타 스타일) + 칭호
- **업적 등급**: U → R → AR → SAR → MUR → P (P는 티어 계산 제외, 개발자 전용)
- **컬렉터 티어**: 몬스터볼(1~200) / 슈퍼볼(201~600) / 하이퍼볼(601~1500) / 마스터볼(1501+)

---

## 트러블슈팅 기록

### 이미지 저작권 (2026-04-07)
- **문제**: 포켓몬 코리아로부터 공식 이미지(pokemonkorea.co.kr) 사용 불가 통보
- **해결**: scrydex EN/JP 이미지로 대체. CardImage 위젯에서 pokemonkorea URL 자동 차단 후 카드 뒷면 표시
- **카드 뒷면 URL**: `https://images.scrydex.com/pokemon/card-back/medium`

### scrydex 이미지 URL 패턴
- EN: `https://images.scrydex.com/pokemon/{tcgplayer_card_id}/medium` (예: `sv4pt5-53/medium`)
- JP: `https://images.scrydex.com/pokemon/{jp_set_id}-{number}/medium` (예: `sv4a_ja-330/medium`)
- 카드 뒷면: `https://images.scrydex.com/pokemon/card-back/medium`
- 모두 HTTP 200 반환 확인됨

### pokemoncard.co.kr E등급 = RRR
- 사이트에서 E등급으로 표기된 카드 = DB의 RRR (VMAX/VSTAR/V-UNION 고레어)
- `no_wrap_by_admin` span에서 실제 rarity 텍스트 파싱 (RRR/RR 등)
- HP: `hp_num[^>]*>HP(\d+)`, 타입: `symbol/type(\d+)\.png` → TYPE_MAP

### 고레어 분류 기준
- `HIGH_RARE_CODES = ["SSR","SAR","BWR","CSR","CHR","UR","SR","AR","HR","ACE","RR","RRR","PR","H"]`
- SV-P 프로모: rarity_code IS NULL, `official_card_code LIKE 'SVP%'`
- V-UNION 5장: rarity_code IS NULL, 수동으로 RRR 설정

### super_type 대소문자
- DB 저장값은 `"POKEMON"` (대문자), 파싱 시 반드시 `.upper()` 비교

### EN_SET_MAP 주요 수정 이력
| KR set | 이전 | 수정 | 근거 |
|--------|------|------|------|
| bw5s | bw5 | bw6 | 뮤 EX → bw6-120 |
| bw7 | bw8 | bw7 | Skyla → bw7-149 |
| sm6b | sm75 | sm7 | Articuno GX → sm7-154 |
| sm8b | sma | sm9 | Morgan → sm9-178 |
| swsh10a | swsh10 | swsh11tg | Parasect → swsh11tg-TG01 |
| sv7 | sv7 | sv8 | Exeggcute → sv8-192 |
| sv8 | sv8 | sv4 | Snorunt → sv4-188 |

---

## 다음 우선순위

1. **거래 완료 처리** — SOLD 시 PriceSnapshot 자동 생성 (APP source)
2. **eBay Finding API** — MEGA/BW 593장 해외 시세 + 이미지
3. **FCM 알림** — 채팅 새 메시지, 관심 카드 가격 변동
4. **업적 시스템** — HP/card_type 기반 (크롤링 완료 후)

---

## 용어 정책

- 생카드 → **RAW** / 매입가 → 사용 금지
- 총 자산 = 평균시세 × 수량 합산
- 가격 = 1의 자리 반올림 + 콤마 포맷 (만원 표기 제거)
