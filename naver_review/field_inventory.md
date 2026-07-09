# naver_review/data.js 필드 인벤토리 (실측, 1362건)
| 필드 | non-null | 의미 |
|---|---|---|
| psid | 1362 | 원본 고유 id (export raw_id) |
| cid | 1362 | 우리 card_id (100% 매핑, 이미지 100% 보유) |
| nm/setn/col/rar | 1362 | 카드명/세트/번호/레어도 |
| cstat/gco/gv | 1362/433/433 | RAW vs GRADED + 등급사/등급 |
| price | 1362 | NAVER 가격(KRW) |
| jp_krw/en_krw | 1297/1191 | JP/EN 참고가(KRW) |
| nvjp/nven | 1297/1191 | NAVER/JP·EN 비율 (오염 감지: 1.0 근처/초과=JP복붙) |
| title | **916** | 제목 원문 (446 없음) |
| url | **916** | cafe.naver.com 원문 (446 없음=SOURCE_EVIDENCE_MISSING) |
| td | 1362 | 거래일 |
| vs | 1362 | 기존 라벨(PENDING 915/VALID 447) — ★재검증 대상, 신뢰X |

## ★없는 것
- **네이버 원본 post 이미지 필드 없음** → 임베드 불가, `원문 열기` URL 클릭으로만.
- url 없는 446건(기존 VALID 다수) = 근거 불가 → 자동 VALID 금지, NEEDS_MANUAL.

## 있는 것 (review_v2 활용)
- **우리 카드 이미지 342/342 cid(100%)** = `scanner/data/cards/{cid}_jp.png`(+ko/en) → 매핑 검증용 표시.
