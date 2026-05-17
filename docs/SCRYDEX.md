# Scrydex 매핑 툴

## 목적
고레어 KO 카드(jp_ref/en_ref=NULL)에 scrydex ref를 수동 매핑

## 사용법
`localhost:8082/data/scrydex_mapper.html`

| 조작 | 동작 |
|------|------|
| 클릭 | JP ref 저장 (ref에 `_ja-` 포함 시 자동 감지) |
| Shift+클릭 | EN ref 저장 |
| X키 | 스킵 (NO_JP / NO_EN 저장) |
| ←→ | 이전/다음 카드 |

- 저장 즉시 DB 반영 (`/scrydex/save` API)
- 같은 포켓몬 연속 시 재검색 안 함 (결과 유지)

## KO→EN 자동번역
- `scanner/data/ko_en_pokemon.json` — PokeAPI 1025종 매핑
- 카드 이동 시 영어 이름 자동완성 후 검색

## ref 포맷
- JP: `{set}_ja-{number}` (예: `swsh12a_ja-262`)
- EN: `{set}-{number}` (예: `swsh12pt5gg-GG70`)

## 관련 API (scanner/main.py port 8082)
- `GET /scrydex/unmapped` — 미매핑 카드 목록
- `GET /scrydex/search?q={name}&page={n}` — scrydex 검색
- `POST /scrydex/save` — `{card_id, jp_ref, en_ref}` → DB 저장

## 현재 상태
- 미매핑 대상: 437개 (SSR/SAR/UR/SR/AR/HR 등 고레어)
