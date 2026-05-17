# 트러블슈팅 로그 — 2026-05-09 세션

---

## 이슈 1: 리스트/상세 KO 예상가 불일치

**증상**
카드 목록(마켓 화면)에 표시되는 KO 예상가와 카드 상세 페이지의 KO 예상가가 서로 다른 값으로 나옴. 예: 목록에서 120,000원이던 카드가 상세 진입 시 105,000원으로 표시.

**원인**
목록 쿼리에만 `popularityMultiplier`(인기도 가중치) 곱셈 로직이 추가 적용되어 있었고, 상세 페이지는 해당 승수 없이 기본 공식(EN scrydex × 환율 × 계수)만 사용. 두 경로의 계산 공식이 달랐음.

**해결**
`popularityMultiplier` 승수를 제거하고, list/detail 모두 동일한 기본 공식으로 통일.

**재발 방지**
KO 예상가 계산 로직을 단일 유틸 함수로 추출. 목록 쿼리와 상세 쿼리 양쪽에서 같은 함수를 호출하도록 리팩토링. 공식 변경 시 한 곳만 수정하면 전파됨.

---

## 이슈 2: scrydex JP slug가 EN column에 저장 (3개 카드 오염)

**증상**
비크티니, 라티아스 ex, 뮤 ex RR 의 영문 시세 조회가 실패하거나 잘못된 카드 데이터를 반환. EN scrydex 가격이 아예 없거나 다른 카드 가격으로 나옴.

**원인**
scrydex 매핑 작업 중 JP slug와 EN slug를 혼동하는 버그가 존재. 해당 3개 카드의 `en_scrydex_ref` 컬럼에 JP slug 값이 잘못 저장됨.

**해결**
DB를 직접 수정하여 3개 카드의 `en_scrydex_ref` 컬럼에 올바른 EN slug를 저장.

**재발 방지**
`scrydex_mapper.html` 저장 시 JP/EN 컬럼 교차 검증 로직 추가 예정. JP slug 패턴(`-jp` suffix 또는 JP 전용 URL 구조)이 EN 컬럼에 들어오면 경고 표시.

---

## 이슈 3: 메가리자몽Y ex MUR KO 예상가 오류

**증상**
메가리자몽Y ex MUR의 KO 예상가가 509,680원으로 표시. 실제 시장가 대비 현저히 낮음(실제 ~775,050원 수준).

**원인**
DB에 과거에 수집된 stale `SCRYDEX_JP` 가격 레코드가 남아있었고, KO 예상가 재계산 시 이 오래된 낮은 JP 가격이 반영됨. scrydex JP 사이트의 실제 현재가보다 낮은 과거 스냅샷이 계산에 사용된 것.

**해결**
해당 카드의 stale `SCRYDEX_JP` 레코드 삭제 후 KO 예상가 재계산 → 775,050원으로 정상화.

**재발 방지**
`price_scrydex.py` guard 로직 구현. PSA10 가격 70% 급락 또는 PSA grade 역전 감지 시 eBay Finding API로 교차검증. 오염/이상치 확인 시 DB 저장 스킵하고 `price_anomalies` 테이블에 이력 기록.

---

## 이슈 4: 뮤 ex SAR 마켓 목록 미표시 (DISTINCT ON 버그)

**증상**
마켓 화면에서 뮤 ex SAR 카드가 목록에 나타나지 않음. 다른 세트의 뮤 ex는 표시되는데 SAR만 누락.

**원인**
`CardRepository` 마켓 목록 쿼리에 `DISTINCT ON (name, rarity)` 적용. 같은 이름("뮤 ex")에 같은 레어도(SAR)인 카드가 여러 세트에 존재할 경우, 첫 번째 카드만 남기고 나머지는 제거됨. 결과적으로 동명 다세트 카드 중 하나가 항상 누락되는 구조적 버그.

**해결**
전체 마켓 목록 쿼리에서 `DISTINCT ON (name, rarity)` 제거. 카드 고유 ID 기준으로 distinct 처리하도록 변경.

**재발 방지**
마켓 목록 쿼리 변경 시 동명 다세트 카드(뮤 ex SAR/SR, 피카츄 V FULL ART 등)가 모두 표시되는지 확인하는 테스트 케이스 추가.

---

## 이슈 5: 판초 피카츄 PSA10 scrydex 가격 오염

**증상**
판초 피카츄 (리자몽 X) PSA10 가격이 $695로 표시. 전날까지 $22,000 수준이던 값이 갑자기 극단적으로 낮아짐.

**원인**
scrydex 사이트에서 "판초 피카츄 (리자몽 X)"에 해당하는 slug가 실제로는 다른 카드(리자몽 X 일반판 등)의 PSA10 데이터를 반환하는 오류 발생. 크롤러가 이 잘못된 $695 데이터를 그대로 DB에 저장하여 기존 $22,000 값을 덮어씀.

**해결**
오염된 레코드 수동 삭제 후 이전 정상 값으로 복원. `price_anomalies` 테이블에 이번 오염 이력(오염값 $695, 복원값 $22,000, 발생일)을 기록.

**재발 방지**
`price_ebay.py` + `price_scrydex.py` guard 구현:
- PSA10 가격 70% 이상 급락 감지 시 자동으로 eBay Finding API 교차검증 실행
- eBay 실거래가와 크게 차이나면 오염으로 판정, DB 저장 스킵
- `price_anomalies` 테이블에 감지 이력 저장, 어드민 `/alerts` 페이지에서 확인 및 수동 해결 처리

---

## 이슈 6: KO 예상가 vs 차트 불일치 (계수 fallback 버그) — 2026-05-09

**증상**
레쿠쟈 VMAX HR 등 EN/JP 레어도별 전용 계수(`ko_coef_en_HR` 등)가 없는 카드에서
KO 예상가 대표값(607,170원)과 차트 오른쪽 끝값(410,570원)이 크게 다르게 표시됨.

**원인**
`saveKoEstimatedSnapshots()`의 `resolveCoeff` fallback이 `globalCoefficient`(0.495, NAVER_CAFE 기반 전체 계수)를 사용.
`getCardPriceSummary()` 차트는 `en_GLOBAL`(0.336)을 fallback으로 사용.
레어도별 계수(`ko_coef_en_HR`)가 DB에 없으면 두 경로가 다른 fallback을 사용 → 불일치.

**해결**
`saveKoEstimatedSnapshots()`에서 `en_GLOBAL` / `jp_GLOBAL`을 source별 fallback으로 분리:
```java
double globalEnFallback = rarityCoeffs.getOrDefault("en_GLOBAL", globalCoefficient);
double globalJpFallback = rarityCoeffs.getOrDefault("jp_GLOBAL", globalCoefficient);
double srcGlobalFallback = "SCRYDEX_EN".equals(src.getSource()) ? globalEnFallback : globalJpFallback;
```

**재발 방지**
차트 마지막 값 = 대표가 원칙: `buildKoLineFromSnaps`와 `saveKoEstimatedSnapshots` 둘 다 동일한 계수 경로 사용 필수.
새 계수 추가 시 `en_{era}_{rarity}` 또는 `en_{rarity}` 키 형식 준수.

---

## 이슈 7: scrydex JP RAW에 PSA 가격 혼입 — 2026-05-09

**증상**
레쿠쟈 VMAX HR JP 데이터에 ¥900,000(≈835만원) 저장.
릴리에 SR에 ¥750,000, ¥1,200,000 저장 등 — HR cap(200만원), SR cap(500만원) 초과.

**원인**
scrydex가 해당 카드 페이지에서 RAW 가격 대신 PSA10 가격을 반환하는 경우 발생.
스크래퍼는 정상적으로 scrydex 데이터를 가져온 것이고, scrydex 자체 데이터 품질 문제.

**해결**
레어도별 cap 초과 SCRYDEX_JP RAW 스냅샷 10건 삭제.
`isJpRawSuspect()` (Java)가 cap 초과분을 KO_ESTIMATED 계산에서 이미 제외하고 있었으나,
JP 차트에는 그대로 노출되고 있었음 → 삭제로 해결.

**재발 방지**
`sanitize_raw()` (Python) 강화:
- `RAW > PSA10` 위반 데이터 저장 전 제거 (이전: × 1.3 허용)
- `PSA10 < PSA9` 순서 위반 시 PSA 기준 전체 무효화
- `save_history()` guard에 `PSA10 < RAW × 0.9` 체크 추가

원칙: **PSA10 > RAW > PSA9** 가격 순서 위반 시 해당 데이터 의심.

---

## 이슈 8: /tmp/ 스크립트 버전 관리 밖 운영 — 2026-05-09

**증상**
`PriceSyncScheduler.java`가 `/tmp/naver_cafe_auction_scraper.py`, `/tmp/recalc_coefficients.py`,
`/tmp/ko_promo_price_scraper.py`를 직접 참조. 재부팅 시 /tmp 초기화 → 스크립트 소실 위험.
또한 `recalc_coefficients.py`에 Python이 KO_ESTIMATED를 직접 생성하는 `regenerate_ko_estimated()` 함수 잔존.

**해결**
세 스크립트를 `python/` 디렉토리로 이동 후 이름 정리:
- `python/recalc_coefficients.py`
- `python/price_naver_cafe.py`
- `python/price_promo_ebay.py`

`regenerate_ko_estimated()` 함수 삭제 — KO_ESTIMATED는 Java 스케줄러만 생성.
`PriceSyncScheduler.java` 경로 업데이트.
모든 스크립트에서 DROP된 `currency` 컬럼 INSERT 제거.

**재발 방지**
동기화 스크립트는 모두 `python/` 아래 버전 관리. `/tmp/`에 스크립트 두지 않는다.

---

## 이슈 9: DC1 (Double Crisis) 카드 KO 예상가 과대추정 — 2026-05-09

**증상**
마그마단의 그란돈 EX, 아쿠아단의 가이오가 EX의 KO 예상가가 22.9만원으로 표시.
실제 한국 시장가(6~12만원, 9~14만원) 대비 2배 이상 과대추정.

**원인**
DC1 (Double Crisis) 영문판 세트는 극소 프린트로 영문 수집가 시장에서 $468 USD에 거래됨.
한국 플레이어는 일본판 CP1 버전을 거래 (훨씬 저가), 영문 DC1을 거래하지 않음.
기존 `en_GLOBAL` (0.336) 계수는 이 시장 괴리를 반영하지 못함.

JP scrydex (cp1_ja-6/cp1_ja-15)는 $1,149 RAW를 반환하나, PSA9($678) < RAW($1,149) 위반으로
오염 데이터로 추정 → spread guard (JP/EN > 2x) 발동 → EN 사용
결국 en_GLOBAL × $468 = 228,000원으로 과대추정.

**해결**
DC1 세트 전용 era (`DC1`) 도입:
1. `GlobalPriceService.resolveEraFromCard(Card)` 추가:
   - `en_scrydex_ref`가 `dc1-`로 시작하면 era = "DC1" 반환
   - 기존 `resolveEra(officialCardCode)` 위임 그 외
2. `saveKoEstimatedSnapshots`, `refreshKoEstimatesFromSnapshots`, `getCardPriceSummary`의
   `resolveEra(card.getOfficialCardCode())` → `resolveEraFromCard(card)` 교체 (3곳)
3. DB에 `ko_coef_en_DC1_RR = 0.12` 삽입
4. 결과: 가이오가 22.9만 → 8.2만원, 그란돈 22.9만 → 8.1만원 (range 6.9~9.4만)

**재발 방지**
DC1 외 DC 시리즈 세트 추가 시 `resolveEraFromCard`에 ref prefix 체크 추가.
XY era 내 수집가 특화 세트는 별도 era 처리가 필요할 수 있음 (en_scrydex_ref prefix 기반).
