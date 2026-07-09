# 포켓폴리오 — 세션 핸드오프 & 운영 런북

> **다음 세션 시작점.** 현재 상태 + "어떻게 하는지"(빌드·업로드·배포·DB) 절차. 매 세션 끝에 「현재 상태」 갱신.

---

## 📍 현재 상태 (2026-07-10 갱신 — 1.2.0 오리파 STEP1+2 mock 완료 / TestFlight 대기 + 노트북 마이그레이션)
- **출시/배포 완료 (App Store)**: **1.0.7** — 빌드 `202607052009` (토스 디자인 전면 개선), main @ `6a993b8b`. **릴리즈 트랙 CLOSED.**
- **현재 개발 트랙**: **1.2.0 오리파 플랫폼** — `feat/oripa-1.2.0` 워크트리(`/Users/fury/pokemon-card-app-oripa`), main서 분기. **STEP 1(진입 mock 4화면 MY→오리파홈→매장목록→매장상세→오리파상세) + STEP 2(번호 오리파 뽑기 mock) 구현완료.** STEP2 = 확인시트→봉인더미 자동추출→덮개 까기(5%↑ 위치유지·이어까기·60/82% 햅틱)→[상품 확인]→상품판 47 자동스크롤(상품 빠져 빈자리)→결과 보관/교환→다시뽑기, 전부 **세션 in-memory(백엔드 0)**. **TestFlight 1.2.0 build `202607082352` Transporter 로드됨 → 사용자 전송 대기.** 다음 = 실기기 손맛 판정 → `peelDist`/노출밴드/햅틱 임계 튜닝 → 상품봉인 오리파 → 파트너센터 → 백엔드. ★진실원 = feat/oripa-1.2.0의 `docs/ORIPA_STEP2_SPEC.md`. ★오리파 상품 = 사장님 업로드(카드 DB/CDN/cardId 무관, image 필드=asset/미래 S3 URL).
  - ⚠️ "1.0.7 심사 중/심사 충돌" 류는 **historical** — 현재상태 추론에 쓰지 말 것. App Review 분석은 사용자 명시 요청 시만.
  - 1.0.7 = feat/toss-restyle 13커밋 머지: 전 화면 토스 문법 통일(공용 킷 `app_list_ui.dart`) + 모션/햅틱 레이어 + 카드 틸트·차트 스크럽 + 엠티스테이트 시스템. 아카이브 태그 `arch/toss-restyle-1.0.7-20260705`.
  - ★정식 릴리즈 IPA는 **CloudFront dart-define 2종 필수** (`BASE_URL=https://d33b273n14t3ne.cloudfront.net` / `CARD_CDN_BASE=https://d3shjhylvfe40j.cloudfront.net/cards/v1`) — 평가용(TestFlight 확인용) 빌드와 구분. 빌드 후 App.framework strings로 URL 박힘 검증.
- **업데이트 게이트**: 과거 계획 = 1.0.7 출시 시 S3 `app-config/version.json` minBuild 상향(첫 발동). **1.0.7 출시됨 — 실제 게이트 발동 여부는 미확인(내가 단정 안 함), 필요 시 사용자 확인.**
- **브랜치(전부 origin push됨, 2026-07-10)**: `main`(87075533) · `feat/oripa-1.2.0`(오리파 구현, 워크트리 `pokemon-card-app-oripa`) · `feat/oripa`(웹 프로토+1.2.0 핸드오프, 워크트리 `pokefolio_oripa`) · `backup/laptop-migration-20260710`(밀기 전 untracked 343개 백업) · `capture/prod-20260703`(서버 배포 트리).

### 💾 노트북 마이그레이션 (2026-07-10) — 새 노트북 세팅 시 읽어라
- **★A~Z 전체 상세 = [`docs/LAPTOP_MIGRATION_20260710.md`](LAPTOP_MIGRATION_20260710.md)** (메타몽 KREAM 에이전트·scanner 47GB·로컬 DB·시크릿 7종 전수 + 순서).
- **git은 전부 origin에 있음**(위 브랜치). 새 노트북: `git clone` → 오리파 이어가려면 `git worktree add ../pokemon-card-app-oripa feat/oripa-1.2.0`.
- **★git에 없는 수동 백업 필수 파일(밀면 소실 → 빌드/서명/배포 불가)**: `front/ios/Runner/GoogleService-Info.plist` · `front/android/app/google-services.json` · `~/pem/pokefolio-upload.jks`(안드 키스토어) · `~/.appstoreconnect/private_keys/AuthKey_HY8YGY46VK.p8` + `AuthKey_VL83MMC8WW.p8`(ASC API 키) · 로컬 `.env`류. → 새 노트북에 복사할 것.
- **Claude 메모리**: `~/.claude/projects/-Users-fury-pokemon-card-app/memory/` 는 로컬 — 밀면 사라짐. 백업하거나, 이 문서 + `docs/ORIPA_STEP2_SPEC.md`로 이어갈 것.
- **오리파 이어가기 진입점**: `docs/ORIPA_STEP2_SPEC.md`(feat/oripa-1.2.0) + `~/pokefolio_oripa/oripa_demo/ORIPA_1_2_0_HANDOFF.md`(feat/oripa).
- **prod 백엔드**: LIVE (Lightsail). 서버 트리 = capture/prod-20260703 @ 7a8a8892. ★리빌드 전 class-diff 게이트 + 기능 스모크(게시판·me 2종·이미지·시세) 필수.
- **Android**: 1.0.6 vc5 비공개 알파 LIVE(구글로그인 검증 완료). 테스터 12+ × 14일 클록 진행 중. 1.0.7 디자인 반영 AAB는 iOS 통과 후.
- **다음 사이클: 1.1.0 오리파 플랫폼** — 오프라인 매장 입점형 **중개** 모델(우리=틀: 매장 콘솔 생성기 + 중앙 추첨 + 포인트 지갑 + 매장별 보관함/배송 + 정산). 원칙: **추첨·돈=플랫폼 / 재고·배송=매장**, 판매 시작 후 구성 동결, 포인트 교환가 승인 시 LOCKED. 유저 플로우: 원화→포인트 충전→뽑기→보관함(매장별)→포인트 교환 or 모아서 배송(매장별 무료배송 기준).
  - **최우선 산출물 = 영업용 데모 3종**: ①매장 콘솔 데모 웹(실카탈로그 검색 연동 생성기 — 킬샷) ②앱 리빌 데모(feature flag+mock, 틸트/광택 재활용) ③원페이저. 콘솔 데모부터.
  - 법률 검토(선불업·전금법 / 사행성) 실결제 전 필수 — 목업 데모 영업은 무관하게 선행 가능. PG=포트원/토스 "파트너 정산" 하위몰 구조.

---

## 🏗 프로젝트 구조
- `back/` Spring Boot (Java 20, port 8080) — prod 배포 대상
- `front/` Flutter iOS (3.41.4) — App Store 앱
- `grading/`(8081) `scanner/`(8082) FastAPI
- `admin/` React 웹 (nginx 호스트, prod `/admin/*`)

---

## ⚙️ 운영 런북 (HOW TO)

### 1. IPA 빌드 (Flutter iOS) — ★사용자 명시 요청 시에만
```bash
cd front
flutter clean    # 필수 (시뮬 run 후 안 하면 x86_64 섞여 App Store 409 거부)
flutter build ipa \
  --dart-define=BASE_URL=https://d33b273n14t3ne.cloudfront.net \
  --dart-define=CARD_CDN_BASE=https://d3shjhylvfe40j.cloudfront.net/cards/v1 \
  --build-number=$(date +%Y%m%d%H%M)   # 타임스탬프. 직전 빌드번호보다 커야 ASC 수락
```
- 산출물: `front/build/ios/ipa/front.ipa`
- `pubspec.yaml` version = App Store 버전 (현재 `1.0.1`). 새 버전이면 여기 bump.

### 2. TestFlight 업로드
```bash
open -a Transporter "/Users/fury/pokemon-card-app/front/build/ios/ipa/front.ipa"
```
→ 사용자가 Transporter에서 **전송** 클릭 → ASC 처리 ~10-30분 → TestFlight 등장.

### 3. ASC 심사 제출
- appstoreconnect.apple.com → 배포 → iOS 앱 버전 1.0.x
- **빌드 섹션**에서 업로드된 빌드 선택 → **"이 버전에서 업그레이드된 사항"**(릴리즈노트) 작성 → **저장**(먼저!) → **심사에 추가** → 제출
- 심사정보: 데모로그인 = Apple 로그인 자가가입 / **폰 테스트번호** = `+82 10-1234-5678 / 123456` (★**Firebase Console 테스트 전화번호** 설정, BE 아님 — 거래 폰인증 게이트 통과용)

### 4. prod 서버 SSH
```bash
ssh -i /Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120
```
- 코드 repo: `/opt/pokefolio/app` (git, 브랜치 `feat/trade-active-counterparty`)
- compose: `/opt/pokefolio/app/docker-compose.prod.yml`
- env: `/opt/pokefolio/.env.prod`
- 컨테이너: `pokefolio-back`(8080) `pokefolio-postgres` 등 (docker compose 4개)

### 5. prod DB 쿼리
```bash
ssh -i ~/pem/... ubuntu@52.78.3.120 \
 "docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \"SELECT ...\""
```
- DB `pokemon_card_db`, user `pokefolio`, 테이블 **복수형**(cards, trade_posts, buy_orders, price_snapshots, assets ...)

### 6. ★BE 배포 (추측 금지 — 사고 이력 있음)
**★중요: Flyway 안 씀(의존성 없음) + `ddl-auto=validate`.** → 마이그 **수동 적용 먼저**, 코드 배포는 그 다음 (순서 어기면 validate 실패로 백엔드 안 켜짐).
1. **백업**: `ssh ... "docker exec pokefolio-postgres pg_dump -U pokefolio -d pokemon_card_db -t <테이블> > /tmp/backup_$(date +%Y%m%d_%H%M).sql"`
2. **마이그 수동 적용**: `cat back/src/main/resources/db/migration/V*.sql | ssh ... "docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -v ON_ERROR_STOP=1 --single-transaction"`
   - 신규 NOT NULL 컬럼엔 `DEFAULT` 넣기 (배포 윈도우에 구버전 코드 INSERT가 NULL 위반 안 하게)
3. **코드**: `git push origin feat/admin-erp:feat/trade-active-counterparty`(ff) → prod `cd /opt/pokefolio/app && git pull --ff-only origin feat/trade-active-counterparty` → `docker compose -f docker-compose.prod.yml build back && docker compose -f docker-compose.prod.yml up -d back`
4. **검증**: `docker logs pokefolio-back --tail 30 | grep -iE "Started|Tomcat started|ERROR|HHH"` (Started + validate 에러 없음 확인)
- ★prod 직접수정 = 백업+diff+롤백플랜+**사용자 명시 OK** 후에만.

### 7. 도메인/CDN
- `BASE_URL` = `https://d33b273n14t3ne.cloudfront.net` (CloudFront → prod 백엔드). **해외 리뷰어 도달성 fix(4번째 반려)**. /api/* + 쿼리스트링 forward 됨(검증).
- 카드 이미지 CDN = `https://d3shjhylvfe40j.cloudfront.net/cards/v1`
- **도메인 안 바꿔도 됨** — 빌드에 BASE_URL 고정, prod 안 이사함.

### 8. 점검 모드 (maintenance)
- S3 `app-config/maintenance.json` → `{"maintenance":true}` 재업로드 + CloudFront invalidation
- ★게이트는 1.0.1+ 클라에만 있음 (라이브 1.0은 게이트 없어 효과 X)

---

## 🚫 핵심 규칙 / 제약 (절대)
- **시세 freeze** — MANUAL_FLOOR만, 모델 안 건드림 (`[[project-chase-pricing-model-status]]`)
- **색상**: 양 빨강 / 음 파랑 (CTA 초록 보존)
- **등급사**: PSA / BRG 만 (CGC·BGS 금지)
- **이미지**: `resolveCardImageUrl(card)` 전역함수만. pokemonkorea.co.kr URL 금지
- **Codex 협업**: 사전검토 → 구현 → 사후리뷰. Codex prompt 첫 줄 "DO NOT call Write/Edit"
- **IPA 빌드 / prod 배포** = 사용자 명시 신호 시에만
- **출시 타이밍** = 사용자 단독 결정 (defer caveat 금지)

---

## 🌿 브랜치 모델 (정리 후 — `[[project-branch-model]]`)
**정책**: `main` = 앱스토어에 떠 있는 **승인된 버전**(지금 1.0). 1.0.1 **승인 나는 순간** main을 `v1.0.1-rc`로 ff → 그때 `main == dev`. **새 개발은 `dev`에서 분기.** (승인 전 main freeze, dev는 앞서도 됨)
- `main` @ `d579a01a` (태그 `v1.0`) = 1.0 라이브. **1.0.1 승인까지 freeze.**
- `dev` = `feat/admin-erp` (ff 동기화) = 통합 tip. 새 feature 분기 기준.
- 태그 `v1.0.1-rc` @ `8cf1ef04` = 1.0.1 제출본(iPhone전용). **승인 시 main ff 타겟.**
- `feat/admin-erp` = 통합 브랜치(=dev). 정리 후 dev와 동일 — 추후 정리(삭제) 가능.
- `origin/feat/trade-active-counterparty` = **prod 배포 브랜치 (삭제 금지)**. prod는 이 origin에서 pull.
- ★**미푸시**: 위 7커밋 + 태그 + dev 동기화 전부 로컬. origin/dev는 364 behind(stale). 푸시는 사용자 신호 시.

---

## ▶️ 다음 작업
1. **1.0.1 심사 결과 대기** (~1-2일) — 승인 시: `git checkout main && git merge --ff-only v1.0.1-rc && git tag v1.0.1` → 자동출시. 반려 시 사유 대응.
2. ~~브랜치 dev 동기화 + origin 푸시~~ ✅ 완료 (working tree 정리 + dev=admin-erp ff + `origin/dev`·태그 푸시)
3. 로드맵: 게시판 → 경매 (`[[project-board-auction-roadmap]]`) — **dev에서 분기**

---

## 📚 상세 메모 (MEMORY.md 인덱스에서 로드됨)
`reference_prod_server` · `project_branch_model` · `project_trade_language_scope` · `project_ipa_build_command` · `project_cloudfront_migration` · `project_release_1_0_1` · `project_phone_auth_trade_handoff` · `project_chase_pricing_model_status`
