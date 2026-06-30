# 도감 박스 이미지 매핑 — Phase A 도구

**범위**: 우리 DB 의 KO visible 카드가 있는 product 와 pokemoncard.co.kr 공식 사이트의 확장팩(info1) 시리즈를 매핑.
**산출물**: 사용자가 HTML 에서 매핑 확정 후 export 하는 CSV.
**다음**: 별도 cycle 에서 CSV 받아 이미지 다운로드 + 백엔드/프론트 도감 본구현.

## 파일

| 파일 | 역할 |
|------|------|
| `scrape.py` | pokemoncard.co.kr info1/info2/info3 3 페이지 스크랩 → `raw_official.json` |
| `match.py` | `db_products.tsv` + `raw_official.json` fuzzy 매칭 → `match_candidates.json` |
| `review.html` | 정적 HTML — DB product 별 top-3 후보 표시 + localStorage + Export CSV |
| `raw_official.json` | 사이트 스크랩 결과 (548 시리즈 — info1 99 / info2 54 / info3 395) |
| `db_products.tsv` | prod DB ko_visible > 0 product 추출 (268개) |
| `match_candidates.json` | DB 각 product 별 top-3 사이트 후보 + score |

## 실행 순서

```bash
cd python/box_image_mapping

# 1. 사이트 스크랩 (이미 실행됨, 재실행 필요 시)
python3 scrape.py

# 2. DB product 추출 (이미 실행됨, 재실행 필요 시)
ssh -i ~/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120 \
  "docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -t -A -F'|' -c \"
    SELECT p.product_id, p.name,
           COUNT(c.card_id) FILTER (WHERE c.language='KO' AND c.is_visible=true) AS ko_visible,
           MAX(c.created_at) FILTER (WHERE c.language='KO' AND c.is_visible=true) AS latest_card_at
    FROM products p
    LEFT JOIN cards c ON c.product_id = p.product_id
    GROUP BY p.product_id, p.name
    HAVING COUNT(c.card_id) FILTER (WHERE c.language='KO' AND c.is_visible=true) > 0
    ORDER BY MAX(c.created_at) FILTER (WHERE c.language='KO' AND c.is_visible=true) DESC NULLS LAST;
  \"" > db_products.tsv

# 3. fuzzy 매칭 (info1 only — 확장팩만)
python3 match.py
# 전체 카테고리로 확장하려면: python3 match.py --all

# 4. 브라우저에서 review.html 열기
open review.html
```

## review.html 사용법

브라우저에서 그냥 열면 동작. Python 서버 안 띄움.

**상단 메뉴**:
- `자동 일괄 확정 (≥0.90)` 버튼 — score ≥ 0.90 인 product 일괄 확정. 처음에 한 번 누르면 81개 한 번에 끝남.
- `Export CSV` — 확정/pass/수동 모두 포함한 CSV 다운로드. 다음 단계 입력.
- `초기화` — localStorage 비움. 처음부터.

**필터**:
- `전체` / `남은 것만` / `자동(≥0.90)` / `검토(0.70~0.89)` / `pass권장(<0.70)`
- 첫 워크플로우: `자동 일괄 확정` → `검토` 필터로 29개만 확인 → `pass권장` 필터로 158개 한 번에 pass.

**각 row 동작**:
- top-3 후보 이미지 카드 직접 클릭 → 확정
- `top-1 확정 (NN%)` 버튼 — 1번 후보로 확정
- `수동 URL` 입력칸 — 사이트 직접 가서 이미지 URL 복사해 넣으면 수동 매핑
- `매칭 안 함 / pass` — 매핑 안 함으로 표시 (CSV 에 action=pass 로 남음)

**localStorage 키**: `box_mapping_v1`. 같은 도메인(파일) 에서 작업 시 이어서 가능.

## CSV 출력 형식

```csv
product_id,db_name,ko_visible,action,image_url,official_title,score,category,site_card_id
PRD_B269D7FE35F74921BDB2,"MEGA 확장팩 「니힐제로」",38,confirmed,"https://data1.pokemonkorea.co.kr/...","MEGA 확장팩 「니힐제로」",1.0,info1,869
```

action 값:
- `confirmed` — top-3 중 선택 (image_url, official_title, score, category, site_card_id 모두 있음)
- `manual` — 수동 URL 입력 (image_url 만 있음)
- `pass` — 매칭 안 함 (image_url 비움)

## 통계

```text
DB 268 products (ko_visible > 0)
  ≥ 0.90 자동 확정 후보: 81개  (대부분 정확 1.00 매칭)
  0.70~0.89 검토 권장: 29개
  < 0.70 pass 권장: 158개      (BW/DP 같은 옛날 시리즈 — 사이트 info1 에서 빠짐)

→ 사용자 수동 작업: 검토 29개 + 옵션으로 158개 일괄 pass.
   자동 확정 + 일괄 pass + 검토 29개 확정 = 5~10분 작업 예상.
```

## 다음 cycle (별도 신호 후)

```text
1. CSV 받아서 image_url 다운로드 + WebP 변환 + S3 boxes/v1/{product_id}.webp 저장
2. products 테이블에 box_image_url 컬럼 추가 (마이그레이션)
3. 백엔드 endpoint:
   - GET /api/assets/dex          → 시리즈(박스) 그리드 + 보유율
   - GET /api/assets/dex/{productId} → 시리즈 내 카드 + 보유 여부 + 힛카드
4. Flutter 도감 탭 + 박스 grid + 박스 상세 화면
5. 매핑 안 된 product 는 hero card fallback (서버 자동 — rarity priority + 가격순 top 1)
```

힛카드 자동 선정 rarity priority (다음 cycle 백엔드 구현 시 사용):
`MUR > BWR > SAR > SSR > UR > HR > CSR > SR > AR > ACE > RRR > RR > H > R > U > C > S > K > PR`
(PR 은 프로모라 일반 레어도 서열 후순위 — 사용자 명시)
