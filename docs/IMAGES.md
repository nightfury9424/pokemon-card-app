# 이미지 파이프라인

## 현재 상태 (2026-04-30)

| 종류 | 파일명 패턴 | 수량 | 출처 |
|------|------------|------|------|
| EN 이미지 | `{cardId}_en.png` | ~3,373장 | scrydex CDN |
| JP 이미지 | `{cardId}_jp.png` | ~3,549장 | scrydex CDN |
| KO 이미지 | `{officialCardCode}.jpg` | ~412장 | pokemoncard.co.kr 크롤링 |

모두 `/Users/fury/pokemon-card-app/scanner/data/cards/` 에 저장.

---

## 이미지 URL 우선순위

```
1. 로컬 서버  →  http://{IP}:8080/images/cards/{cardId}_jp.png
2. 로컬 서버  →  http://{IP}:8080/images/cards/{cardId}_en.png
3. scrydex CDN  →  https://images.scrydex.com/pokemon/{ref}/medium
4. null  →  CardImage 위젯이 카드 뒷면 표시
```

JP 우선인 이유: KO 카드는 JP와 동일한 일러스트 사용.

---

## Flutter 사용법

```dart
// 항상 이 함수만 사용
final imageUrl = resolveCardImageUrl(card);        // 로컬 우선
final cdnUrl   = resolveCdnImageUrl(card);         // CDN fallback용

CardImage(
  imageUrl: imageUrl,
  cdnFallbackUrl: cdnUrl,   // 로컬 404시 CDN 자동 재시도
  width: 44, height: 62,
)
```

위치: `lib/core/widgets/card_image.dart`

---

## 백엔드 로컬 서빙

Spring Boot `WebMvcConfig`에서 `/images/cards/**` → `card.image.dir` 정적 파일 서빙.

```properties
# application.properties
card.image.dir=/Users/fury/pokemon-card-app/scanner/data/cards
```

---

## scrydex 이미지 다운로드 스크립트

```bash
cd scanner/data
python download_scrydex.py
```

- `scrydex_refs.csv` 읽어서 `{cardId}_en.png` / `{cardId}_jp.png` 저장
- 8 workers 병렬, 이미 있으면 skip
- URL 패턴: `https://images.scrydex.com/pokemon/{ref}/medium`

---

## DB 매핑 확인 (2026-04-30 기준)

- EN/JP 이미지 3,373쌍 → **전부 DB card_id 매핑**
- KO 이미지 412장 → 341장 매핑 (71장은 삭제된 C/U/R 카드)

---

## scrydex ref 패턴

| 카드 종류 | en_scrydex_ref | jp_scrydex_ref |
|-----------|---------------|----------------|
| 일반 SV | `sv4pt5-223` | `sv7a_ja-93` |
| SM-P 프로모 | `NO_EN` | `smp_ja-{번호}` |
| SV-P 글로벌 | `svp-{번호}` | `svp_ja-{번호}` |
| NO_ 접두사 | 해당 언어판 없음 | → null 처리 |
