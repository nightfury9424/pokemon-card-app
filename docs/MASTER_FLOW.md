# PokeFolio 마스터 플로우 (THE 순서) — 2026-06-22 확정

> ★ 우리 전체 진행 순서의 **단일 진실원**. 헷갈리면 이 문서부터. (사용자 확정)

## 현재 상태 (2026-06-22)
- **iOS 1.0.3 = App Store "배포 준비됨"(Ready for Distribution)** = 사실상 라이브 **안전판** 확보. → 1.0.4 생성 가능.
- 53장 카드 추가: DB 3,893 / 스캐너 49장 배포 (4장 보류 = v2 대기)
- 어드민 레어도별 계수 표시버그 = 수정·배포 완료

## ★ 두 번 헷갈린 핵심 (고정)
1. **"심사 기간 동안 SNKRDUNK" = 지금 시작 아님.** UI/UX·게시판·Android를 심사에 넣고 **결과 기다리는 공백 시간**에 SNKRDUNK 동기화를 운영화한다.
2. **SNKRDUNK = 신규 조사 단계 아님.** 이미 수집기·산출물 있음 → 다음 작업은 "사이트 구조 조사"가 아니라 **기존 파이프라인 인수인계 → 운영 동기화 완성**.
3. **매핑 불확실 데이터를 `price_snapshots`에 직접 넣지 않는다.** 오염되면 v8 근거 자체가 망가짐 → staging/raw evidence만, **확정 매핑만 승격**.

## THE 순서 (1→8)
1. **UI/UX 브랜치 정리 → dev 통합** (UI/UX 변경 검토, iOS 회귀 테스트, 게시판과 충돌할 커밋 정리). main/release 아님, dev에만. 1.0.3 심사 무관.
2. **게시판 풀스택 + moderation 완성** — 글/댓글, 신고·차단, 금칙어, 운영자 삭제·제재, 어드민 모더레이션, 약관·24h 검토 정책, 탈퇴·차단 사용자 콘텐츠 처리. ★게시판은 **1.0.4에서 숨기지 않고 실제로 보이게 심사**(Apple 2.3.1 hidden-feature 회피). 각 글·댓글에서 신고/차단 직접 접근. (백엔드는 미리 prod 배포 가능 — 1.0.3 안 씀)
   - ★**현재 = 프론트 목업뿐, 백엔드 0** (`feat/post-launch-front`의 게시판 커밋 = 스캐폴딩/목업, `feat/moderation-backend` 없음). → **백엔드 전부 신규**: posts·comments·카테고리(공지/소식/커뮤니티)·신고·차단 테이블+API + 어드민 모더레이션. 목업을 실 API에 연결 + 글쓰기/댓글 작성 UI.
   - ★단 **모더레이션 인프라는 재사용**: 기존 거래(BUY_ORDER 자동차단·글당 dedup)·문의 신고/차단 패턴 활용. = "게시판 완성"이 아니라 **풀스택 신규 기능**(규모 큼).
3. **Android 완성** — UI/UX·게시판 반영된 공통 Flutter 기준: 서명·패키지, Firebase, Google 로그인(애플만 있음→추가), 전화번호 인증, 카메라·사진 권한, 스캔·푸시·딥링크, 실기기 테스트, Play Data Safety·계정 삭제. ★IP(포켓몬) Google도 재검토.
4. **iOS 1.0.4 / Android 심사 제출 (독립)** — 준비되는 쪽부터 독립 제출(다른 스토어·타임라인). 둘 다 UI/UX·게시판·moderation 보이는 상태. 제출 후 기능 변경 최소화.
5. **심사 대기 기간 = 기존 SNKRDUNK 파이프라인 운영화** (아래 정책). 가격 계산엔 아직 미반영.
6. **승인 후 공식 마케팅 출시** — 1.0.4 + Android 공개, 홍보·유입 시작. SNKRDUNK 동기화는 계속 누적.
7. **가격 v8 구현** — 검증된 데이터로: SNKRDUNK JP 체결가 + Scrydex JP RAW + 네이버·당근 KO 체결 근거 비교 → JP sanity + KO 보정. (`docs/PRICE_V8_DESIGN_20260619.md`)
8. **스캐너 hard-negative v2** — 보류 4장(엘풍 ex·메타몽 V·코바르온 AR·러브로스 V) 복귀. 실사진 20장 학습 활용, 전체 재임베딩·회귀 A/B. (`docs/SCANNER_HARDNEG_V2_ISSUE_20260622.md`)

## SNKRDUNK 운영화 정책 (Step 5 상세)
**기존 산출물 인수인계** (조사 X, 운영화):
`snkrdunk_collect.py` · `snkrdunk_probe.py` · `snkrdunk_apparel_catalog` · `snkrdunk_recent_sales_by_apparel` · `snkrdunk_evidence_mapped` · `snkrdunk_to_pokefolio_match_review` (HTML) · `v8_snkrdunk_stage1_catalog_first` 문서

**운영화 작업**:
- 판매완료 데이터 고유키 + 중복 방지(idempotency)
- 상품 ↔ `card_id` 확정 매핑
- 미확정 판매자료 = **staging/raw evidence로만 저장**
- card_id 확정된 체결 건만 **`SNKRDUNK_SOLD_JP` 이력으로 승격**
- 과거 판매내역 backfill 가능 범위 확인
- daily cron + 모니터링(수집 성공률·신규건수·중복·매핑 실패)
- ★ **충분히 검증 전 v6/현재 앱 가격 계산에 사용 금지**

## 트랙 그림
```
출시 트랙:  1 UI/UX → 2 게시판 ──→ 4 iOS 1.0.4 심사 ──→ 6 출시
                       └ 3 Android 병행 ──→ 4 Android 심사 ┘
데이터 트랙: ───────────(5 심사 대기 공백)→ SNKRDUNK 운영화 ──누적──→ 7 v8 → 8 v2
```

## 지금 다음 액션
**SNKRDUNK 지금 시작 X.** 먼저 **UI/UX 브랜치 현황 + 게시판 브랜치 정확히 조사 → 통합 계획 보고** (Step 1 착수).

## 관련 문서
- `docs/SESSION_HANDOFF_20260622.md` — 최근 세션 핸드오프(현재 상태·다음 액션)
- `docs/CARD_ADD_FLOW.md` — 카드 추가 재사용 플레이북
- `docs/SCANNER_HARDNEG_V2_ISSUE_20260622.md` — 스캐너 v2 + 보류 4장
- `docs/PRICE_V8_DESIGN_20260619.md` — 가격 v8 설계
- `docs/CARD_SET_IMPORT_RUNBOOK.md` — 카드 SET 통째 등록(갭필과 별개)
