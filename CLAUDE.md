# PokeFolio — CLAUDE.md

## AI 협업 원칙 (필수 준수)

> **Claude는 모든 주요 작업에서 Codex와 함께 움직인다.**
>
> - 구현 전: Codex와 레퍼런스 수집 및 설계 토론
> - 구현 후: Codex에게 코드 리뷰 요청
> - 버그/이슈: Codex와 공동 디버깅
> - 사용자 답변: 두 관점을 종합해 일목요연하게 정리해서 전달
>
> 단순 수정(오타, 한 줄 패딩)은 예외. 기능 설계·복잡한 UI·백엔드 로직은 반드시 Codex와 상의 후 최상의 퀄리티를 추구한다.

## 프로젝트 구조
```
pokemon-card-app/
├── back/       # Spring Boot 4.0.4, Java 20, port 8080
├── front/      # Flutter 3.41.4, iOS
├── grading/    # FastAPI, port 8081 (그레이딩 서비스)
├── scanner/    # FastAPI, port 8082 (DINOv2+FAISS, 동작 중)
│   └── data/cards/  # 카드 이미지 (EN/JP/KO, ~10,237장)
└── docs/       # 상세 문서
```

## 실행 명령어
```bash
# 백엔드
cd back && ./gradlew bootRun

# 그레이딩
cd grading && source venv/bin/activate && uvicorn main:app --host 0.0.0.0 --port 8081

# 스캐너
cd scanner && KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES \
  /Users/fury/miniconda3/envs/scanner_v2/bin/uvicorn main:app --host 0.0.0.0 --port 8082

# Flutter
cd front && flutter run
```

## 핵심 규칙

**이미지**: `resolveCardImageUrl(card)` 전역 함수만 사용 (`lib/core/widgets/card_image.dart`)
- 우선순위: 로컬(`/images/cards/{cardId}_jp.png`) → scrydex CDN → null(카드 뒷면)
- `pokemonkorea.co.kr` URL 절대 사용 금지

**시세**: KO 예상가 = EN RAW scrydex × 환율 × 계수
- 백엔드에서 `koEstimatedPrice`로 계산해서 반환
- 가격 포맷: 1의 자리 반올림 + 콤마 + "원"

**DB**: KO 노출 3,425 / 감춤 270 / KO 전체 3,695 (`@SQLRestriction is_visible=true`). ddl-auto: validate
- `nightfury` 유저, `pokemon_card_db` DB
- 감춤 270 = S rarity 258 + K rarity 12 (베이직 포켓몬 commons). C/U/R rarity 는 row 자체 삭제 (legacy)
- 2026-05-29 prod 기준 — Card.java `@SQLRestriction("is_visible = true")` 적용 후 JPQL 카운트가 visible 만 반환

## 상세 문서
| 문서 | 내용 |
|------|------|
| [docs/SETUP.md](docs/SETUP.md) | 새 맥 환경 세팅 |
| [docs/KREAM.md](docs/KREAM.md) | KREAM 메타몽 프로모 시세 자동 수집 (CDP attach + sales API incremental) |
| [docs/IMAGES.md](docs/IMAGES.md) | 이미지 파이프라인 (로컬 서빙, scrydex) |
| [docs/PRICE.md](docs/PRICE.md) | 시세 시스템 (KO/EN/JP, 예상가 계산) |
| [docs/SCANNER.md](docs/SCANNER.md) | DINOv2+FAISS 스캐너 개발 |
| [docs/GRADING.md](docs/GRADING.md) | 그레이딩 알고리즘 |
| [docs/PIPELINE.md](docs/PIPELINE.md) | 번개장터 크롤→라벨→DB 파이프라인 |
| [docs/SCRYDEX.md](docs/SCRYDEX.md) | scrydex_mapper.html JP/EN ref 매핑 툴 |
| [docs/COST.md](docs/COST.md) | API 호출 비용 최적화 패턴 (mutation-aware refresh, silent refresh 등) |
| [docs/ROADMAP.md](docs/ROADMAP.md) | 앱 분석, 시장, 전체 로드맵, 오늘/내일 할 일 |
| [docs/TODO.md](docs/TODO.md) | 기능별 상세 TODO (신고, 가격 파이프라인 등) |
