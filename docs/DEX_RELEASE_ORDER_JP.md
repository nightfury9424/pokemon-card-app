# 도감(dex) 세트 정렬 — 일본판 공식 발매일 기준

> **결론: 도감 세트 목록 정렬 기준은 `products.release_date_jp`(= 일본판 발매일) 최신순이다.**
> 출처 등급: **pokemon-card.com 공식확정 14 + Bulbapedia 기반 2차확정 108 + NULL 3**(JP 대응불명 KO전용). "전부 일본 공식 발매일"이 아님 — 108건은 Bulbapedia 2차이며 공식 페이지 미교차분.
> 한국 발매일이 아니다. KO 발매일이 나중에 필요하면 `release_date_ko`로 별도 컬럼을 추가한다(이 컬럼을 KO로 오해하지 말 것).
> 적용일 2026-06-26.

## 왜 JP 발매일인가
- 목적은 "도감 세트를 대략적인 실제 출시 최신순으로 정렬"하는 것. JP·KO 세트 출시 흐름은 대부분 동일해 상대 순서가 일치한다.
- 기존 정렬(`MAX(created_at)`=DB 적재일 + 세대명 `generationPriority`)은 적재일이 대량 리타임스탬프(2026-06-22)되어 사실상 무의미 → 발매순으로 교체.
- KO 공식 발매일은 단일 출처로 125건 전부 확보가 어려워, JP 공식(pokemon-card.com) + JP 2차(Bulbapedia)로 확정. 차이 발견 시 해당 상품만 예외 보정.

## 데이터
- 컬럼: `products.release_date_jp DATE NULL` (코멘트에 "JP 발매일·KO 아님" 명시). 2026-06-26 마이그레이션.
- 매핑표: `python/catalog_import/dex_release_dates_jp.csv` (product_id, current_name_ko, set_code, release_date_jp, source, status, note).
- 도감 대상 125건 = **122 NOT NULL / 3 NULL**.
  - 공식확정 14 = pokemon-card.com (MEGA 7종 m1~m5 + 스타트덱100/Generations/스페셜덱/ex스타트덱/스타트덱100JP/THE BEST OF XY 등 사용자 확인분).
  - 2차확정 108 = Bulbapedia JP expansions(공식 페이지 미교차분 — "공식 확정" 아님으로 표기).
  - **NULL 3 = JP 대응 불명 KO 전용/특수 구성 상품**: `소드&실드 세트 V`(swshp) · `썬&문 랜덤30장덱`(sm6) · `썬&문 GX배틀부스트 REMASTER`(sm4p). 가짜 날짜·세트코드 추정값 저장 안 함 → NULLS LAST.

## 정렬 로직 (DexService.getDexMain)
```sql
ORDER BY p.release_date_jp DESC NULLS LAST, p.product_id ASC
```
- (구) Java `generationPriority` 세대 재정렬 제거 — 정렬을 SQL 한 곳으로 일원화.
- 동일 발매일(쌍둥이 세트 등)은 `product_id ASC`로 deterministic.
- NULL 3건은 맨 뒤. 현재 도감은 상위 40개만 노출하므로 화면 영향 없음(전부 구세대/비표준).

## 주의 / 함정
- 공유 세트코드 분화 확인 필수: `swsh5i`(일격마스터 2021-01-22 vs 스타트덱100 2021-12-17), `sm4p`(GX배틀부스트 2017-10-20 vs REMASTER NULL), `sm6`(금단의빛 2018-03-02 vs 랜덤30장덱 NULL) — product_id별로 다름.
- `MEGA 스타트덱100 배틀컬렉션`은 카드가 sv8a refs를 재사용해 세트코드가 sv8a로 보이지만 실제 MEGA-era(JP 2025-12-19).

## 롤백
- 백엔드: `docker tag board-pathscoped-menu-20260625 latest && docker compose -f docker-compose.prod.yml up -d --no-build --force-recreate back` (= 5552f2e1, 발매순 이전).
- DB: `ALTER TABLE products DROP COLUMN IF EXISTS release_date_jp;` (백업 `/opt/pokefolio/backups/products_20260626_0114.sql`).

## 미완료 검증 (App Store 제출 전 필수)
- **백엔드 `./gradlew test` 전체 미실행** — 작업 맥에 Docker(testcontainers) 부재로 실행 못 함. 잔여 리스크로 수용하고 TestFlight 업로드(빌드 202606260126)는 진행함.
  - 근거: 이번 변경은 `DexService` 정렬 한정(ORDER BY 1줄 + 죽은코드 제거, 전용 테스트 없음), compileJava 성공, 운영 healthy, 핵심 API smoke 200, 5xx 0, 라이브 도감 순서 정상.
  - **App Store 심사 제출 전 Docker 가능한 환경에서 `cd back && ./gradlew test` 전체 실행으로 닫을 것.**
