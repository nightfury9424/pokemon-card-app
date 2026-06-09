# 승인 직후 체크리스트 (POST-APPROVAL)

> App Store 1.0 승인 알림이 뜨면 **이 순서대로**. 메모리 전수 검색(2026-06-09) 결과 통합.
> 원칙: **심사 중엔 prod 절대 안 건드림.** 아래는 전부 **승인 후** 작업.

---

## 0. 제출/심사 중에 미리 확인
- [ ] **ASC 출시 옵션 = 수동(Manual)** 인지 확인. 자동이면 승인 즉시 공개 → 테스트 DB 정리 창이 사라짐.

---

## 1. 승인 후, "공개(make live)" 전 — prod 작업 (이제 건드려도 안전)

### 1-1. nginx real_ip (CloudFront) — ★이번 세션 CloudFront 마이그레이션 후속
- 이유: CloudFront 붙어서 백엔드가 모든 요청을 CloudFront IP로 봄 → per-IP rate-limit이 유저들 묶어 차단 가능 + 로그에 진짜 IP 안 남음.
- 작업: 호스트 nginx(`/etc/nginx/sites-enabled/pokefolio`)에 추가:
  ```nginx
  real_ip_header X-Forwarded-For;
  real_ip_recursive on;
  # set_real_ip_from <CloudFront origin-facing 대역들> — 아래 명령으로 생성
  ```
- CloudFront 대역 생성:
  ```bash
  curl -s https://ip-ranges.amazonaws.com/ip-ranges.json | \
    python3 -c "import sys,json;d=json.load(sys.stdin);[print(f'set_real_ip_from {p[\"ip_prefix\"]};') for p in d['prefixes'] if p['service']=='CLOUDFRONT_ORIGIN_FACING']"
  ```
- ⚠️ 적용 전 **백업** + `sudo nginx -t`(문법검사) 통과 후 `sudo nginx -s reload`. 임의 IP 신뢰 금지(XFF 위조 방지 — CloudFront 대역만).
- 확인: 적용 후 nginx access log에 CloudFront IP 아닌 **진짜 클라 IP** 찍히나.

### 1-2. 테스트 DB 정리 — [[project-app-store-submission-2026-06-04]]
- 카탈로그(`cards`/`prices`/`price_snapshots`) **보존**, **user + cascade 전체 삭제**:
  assets · trade_posts · buy_orders · chat_rooms · chat_messages · card_interests · post_interests ·
  notifications · reports · blocks · inquiries · 정지이의 · asset_images · fcm_tokens · phone_verify_attempts · trade_settlements · user_warnings
- 절차: **pg_dump 백업 → Codex로 FK 순서 SQL 검토 → 트랜잭션 실행 → 롤백 플랜**. [[feedback-prod-no-direct-modification]]
- ⚠️ **강민형(본인) 계정 보존/삭제 결정 필요.** (좀비 3명은 이번 세션에 이미 하드삭제됨.)
- 출시 전이라 전 계정이 테스트 → is_test 플래그 불필요.

### 1-3. 백엔드 재배포 (대기 큐 — 한 번에)
- **`5b53c4a6`**: 탈퇴 403 메시지 "탈퇴 후 3개월간 동일 계정 재가입 제한" (현재 prod는 구 메시지). + 프론트는 제출 빌드에 이미 포함.
- **per-IP rate limit 100** (`be22274d`, 현재 prod=15) — [[project-phone-auth-trade-handoff]] / [[project-must-before-deploy]] 보안패치 확인.
- 배포 패턴: feat push → prod `git pull --ff-only` → `docker compose ... up -d --build --no-deps back`. 롤백=git reset+rebuild.

---

## 2. 공개 (수동 출시 버튼)

---

## 3. 출시 후 (즉시는 아님)
- **purge cron** (탈퇴 deletedAt < 90일 hard-delete) — **출시+3개월 내 필수**(안 하면 "3개월 후 재가입" 거짓). [[project-account-deletion-fix]]
- **1.0.1 IPA**: 차트 등급칩 빈등급 버그(card_detail:3087) [[project-front-next-build-queue]] + 홈로딩 견고화(백엔드 느릴 때 무한스피너 방지) + 이미지 안뜨는 일부 카드.
- **admin observability dist rsync**: 운영로그/경고/대시보드 페이지(`063ee954` 백엔드는 배포됨, admin 웹은 로컬 build+rsync 필요). [[project-user-event-observability-handoff]]
- **게시판 → 경매** 신기능. [[project-board-auction-roadmap]]
- **전화인증 게이트 완화** (한국번호만 강제 → 완화). [[project-app-store-submission-2026-06-04]]

---

## 핵심 컨텍스트 — 이번(4번째) 반려 & CloudFront 마이그레이션
- 4번 반려 모두 **iPad 무한스피너** = 근본 원인 **해외 리뷰망 ↔ 서울 백엔드(nip.io) 도달 지연/실패** (친구 실물 iPadOS 26.5 + 시뮬 다 정상 = 앱은 멀쩡).
- 해결: **CloudFront 글로벌 엣지**(`d33b273n14t3ne.cloudfront.net`, Free, origin=nip.io:443/CachingDisabled/AllViewerExceptHostHeader) + 앱 BASE_URL 교체 + 로그인 90s timeout.
- 제출 빌드: **1.0.0 (202606090121)**. 커밋: `be96efbe`(cloudfront+timeout) `0f387835`(psa prefill+탈퇴문구) `5b53c4a6`(로그인에러표시+3개월).
- 이미지 CDN(별도 `d3shjhylvfe40j`, S3 origin)은 안 건드림.
