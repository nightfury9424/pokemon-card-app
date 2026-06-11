# 포켓폴리오 — 세션 핸드오프 & 운영 런북

> **다음 세션 시작점.** 현재 상태 + "어떻게 하는지"(빌드·업로드·배포·DB) 절차. 매 세션 끝에 「현재 상태」 갱신.

---

## 📍 현재 상태 (2026-06-11 갱신 — 브랜치 정리 후)
- **App Store 라이브**: **1.0** (승인·출시됨, `main` @ `d579a01a`, 태그 `v1.0`).
- **심사 중**: **1.0.1** — 빌드 `202606111444` (발매판 거래 분리 + 버그픽스 + **iPhone 전용**). 제출 완료, ~1-2일 대기.
  - ★1.0.1 제출 소스 = 태그 **`v1.0.1-rc`** @ `8cf1ef04` (iPhone 전용 빌드설정 포함). **승인 시 `main`을 이 태그로 ff** + `v1.0.1` 태그.
- **prod 백엔드**: LIVE. 배포 브랜치 `origin/feat/trade-active-counterparty` @ `9033afa4` (발매판 BE 포함). 로컬 동명 ref는 stale — origin이 진실.
- **작업 트리 정리 완료**: 미커밋 더미를 논리 8커밋으로 분리(1.0.1빌드설정·gitignore·admin대시보드·scanner증분도구·box매핑파이프라인·크롤러·docs·handoff). 쓰레기(`<stdin>`·ios/build·로그CSV·box 스크랩산출물) gitignore. **`origin/dev`에 푸시됨** (ff, `ad58a78f→4a063981`) + 태그 `v1.0.1-rc` 푸시됨.
- **통합 브랜치**: `feat/admin-erp` = `dev` (ff 동기화 완료) = 최신 통합 tip = `origin/dev`. **새 개발은 `dev`에서 분기.**
- **방금 끝낸 것**: 브랜치 모델 복원(working tree 정리 → dev 동기화) + 1.0.1 소스 태그 고정.

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
