# naver_decisions_v2 export 스키마
review_v2.html "결정 내보내기(JSON)" 출력. card_id별 VALID_SINGLE_RAW만 v8 ground truth로 사용.
| 필드 | |
|---|---|
| raw_id | psid |
| card_id | 우리 cid |
| card_name | nm |
| source_url | 원문 URL (빈값=근거없음) |
| title_raw | 제목 원문 |
| price_krw | NAVER 가격 |
| sold_date | td |
| cstat | RAW/GRADED |
| nvjp | 오염비 |
| decision | VALID_SINGLE_RAW / REJECT_* / NEEDS_MANUAL |
| reject_reason | REJECT_BUNDLE/SEALED/GRADED/WRONG_CARD/WRONG_LANGUAGE/ASK_ONLY |
| reviewer_note | (수동) |

## v8 사용 규칙
- **VALID_SINGLE_RAW 만** KO ground truth (단품 한국 raw 체결).
- REJECT_* / NEEDS_MANUAL / url없음 = 제외.
- VALID 카드 중 SNKRDUNK A급 있는 것 → KO/JP 계수 캘리브레이션.
