# 포켓몬 카드 앱 — CLAUDE.md

## 프로젝트 구조

```
pokemon_card_app/
├── back/   # Spring Boot (Java 17), port 8080
└── front/  # Flutter
```

## 스택

- **백엔드**: Spring Boot, PostgreSQL (`pokemon_card_db`), ddl-auto: validate
- **프론트**: Flutter, go_router, fl_chart
- **인증**: Kakao OAuth2 + JWT
- **이미지**: scrydex (`https://images.scrydex.com/pokemon/{ref}/medium`)

## 핵심 규칙

### 이미지
- KO imageUrl(`pokemonkorea.co.kr`) 사용 금지 — 저작권 이슈
- 반드시 `resolveCardImageUrl(card)` 전역 함수 사용 (`lib/core/widgets/card_image.dart`)
- 우선순위: JP scrydex ref → EN scrydex ref → null(카드 뒷면)
- scrydex 매핑은 반드시 set_id + 번호 조합. 이름 기반(slug) 절대 금지

### DB cards 테이블 주요 컬럼
- `jp_scrydex_ref`: `sv7a_ja-93` 형식 (JP 이미지 + JP 시세)
- `en_scrydex_ref`: `sv4pt5-223` 형식 (EN 이미지 + EN 시세)
- `NO_EN` / `NO_JP`: 해당 언어 버전 없음을 명시적으로 표시
- `rarity_code`: SSR/SAR/BWR/CSR/CHR/UR/SR/AR/HR/ACE/RRR/RR/PR/H/MA/MUR/C/U/TR
- PR 카드 = 프로모 카드 (SM-P, SV-P, SWSH-P 등)

### 시세
- KO 시세: `price_snapshots` 테이블 (RAW/GRADED, 당근/번개/ICU)
- EN/JP 시세: scrydex API (`/api/scrydex/prices/{ref}`)
- KO 예상가 = EN RAW 시세 × 환율 × 계수 (card_detail_screen에서 계산)
- 가격 포맷: 1의 자리 반올림 + 콤마 + "원"

### 용어
- 생카드 → RAW | 등급카드 → GRADED
- "매입가" 표현 사용 금지
- 총 자산 = 평균시세 × 수량 합산

## 주요 API 엔드포인트

| 엔드포인트 | 설명 |
|---|---|
| `GET /api/cards/market?rarities=...&sortBy=price` | 시세 목록. sortBy=price 시 LATERAL JOIN 가격순 |
| `GET /api/cards/{cardId}` | 카드 상세 |
| `GET /api/cards/product/{productId}` | 팩별 카드 목록 |
| `GET /api/assets` | 내 자산 목록 |
| `GET /api/scrydex/prices/{ref}` | scrydex 시세 조회 |

## Flutter 주요 화면 파일

| 파일 | 역할 |
|---|---|
| `lib/features/price/price_screen.dart` | 시세 목록. 가격순=백엔드 재조회 |
| `lib/features/card/card_detail_screen.dart` | 카드 상세 + 차트(KO/EN/JP 탭) |
| `lib/features/card/product_cards_screen.dart` | 팩별 카드 목록 (C/U/TR 필터링) |
| `lib/features/asset/asset_screen.dart` | 자산 관리 |
| `lib/core/widgets/card_image.dart` | `resolveCardImageUrl()` 전역 함수 위치 |

## 백엔드 재시작 필요 상황

Java 코드 변경 후 반드시 재시작 필요 (hot reload 없음):
```bash
# 실행 중인 프로세스 확인
lsof -i :8080 | grep java

# 종료 후 재시작
kill {PID}
cd back && ./gradlew bootRun
```

## SM-P / SV-P 프로모 카드 scrydex ref 패턴

- SM-P 일본 독점: `en_scrydex_ref = 'NO_EN'`, `jp_scrydex_ref = 'smp_ja-{번호}'`
- SV-P 글로벌: `en_scrydex_ref = 'svp-{번호}'`, `jp_scrydex_ref = 'svp_ja-{번호}'`
- HGSS 블랙스타: `en_scrydex_ref = 'hsp-HGSS{번호}'`
- Celebrations(swsh25th) 세트: #1=피카츄VMAX, #2=피카츄V, #3=레쿠우자 — ref 혼동 주의

## MCP 설치 현황

- `sequential-thinking`: ✓ Connected
