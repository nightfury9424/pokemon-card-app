# 세션 핸드오프 — 2026-06-22

> 다음 세션 진입점. ★전체 진행 순서 = `docs/MASTER_FLOW.md` 먼저 읽어라.

## 이번 세션 한 일

### 1. 신규 카드 53장 추가 (갭필) — 플레이북=`docs/CARD_ADD_FLOW.md`
- 퍼널 246→53 (dedup/rematch, 사용자 승인 HTML). **DB 3840→3893** (전부 visible LIVE, 가격백필 SCRYDEX_JP RAW + KO_ESTIMATED).
- 가격 부트스트랩 = `audit/V6_BOOTSTRAP_SNAPSHOT_20260622.json` (CHR 0.342 등, v6 일치). v6 DRY_RUN would-change 0.
- 스캐너 = **49장만 배포** (3840→**3889/57100**, 블루-그린 reload-index 무중단). 가디안 0.958·맥날 0.944·엘풍V복귀 0.816 검증.

### 2. 스캐너 같은-포켓몬 회귀 → 4장 보류
- 신규 4장(**엘풍 ex·메타몽 V·코바르온 AR·러브로스 V**)이 기존 같은포켓몬 스캔 침범 (scan_capture 707→700, 8건).
- 빠른해결 전부 실패(OCR 8/8 추출실패·rot+7제거·top2/3 합의·outlier·실사진 20장 augment 추가). 진단 결정타: **신규클린 > 정답실사진 > 정답클린** = 모델이 카드정체성<포켓몬일러유사성.
- 4장 **스캐너 인덱스에서만 제외**(`scanner/scanner_excluded_cards.json`), DB/앱/시세 정상. 이슈 박제 = `docs/SCANNER_HARDNEG_V2_ISSUE_20260622.md` (P1). 실사진 20장(`~/Downloads/realshots_crops.json`) = v2 학습 시드.

### 3. 어드민 계수 표시버그 수정·배포
- "레어도별 계수 현황"이 `ko_price_coefficients`(Spring 1차계수, CHR **0.932**) 표시 = 실제 적용 **v6 FROZEN_RTR**(0.342, Python v6_apply.py 23:52)와 불일치 → 운영자 오해.
- `admin/src/pages/Price.jsx`만 수정 (제목"Spring 1차 계산 계수·참고용"+배지+노란경고박스+컬럼"1차 계산 계수/예시 금액"+예시금액 약하게). **가격로직/백엔드/DB/배치/버튼/API 무변경.** dist 원자교체 배포 + 브라우저 검증 통과.

### 4. ★마스터 플로우 확정 = `docs/MASTER_FLOW.md`
1.UI/UX dev통합 → 2.게시판 풀스택+moderation(1.0.4 보이게) → 3.Android → 4.iOS1.0.4/안드 심사 → **5.심사 대기 공백에 SNKRDUNK 운영화** → 6.출시 → 7.가격 v8 → 8.스캐너 v2.

### 5. 브랜치 조사 (Step 1 통합계획 시작)
- `feat/post-launch-front` = **UI/UX(카드/MY) + 게시판(목업) 같은 브랜치**, dev 대비 **23앞/19뒤 → rebase 필요**.
- ★게시판 = **프론트 목업뿐**(백엔드/모더레이션 미착수). `feat/moderation-backend` 존재 안 함 → Step 2는 거의 새로 만들어야 함.

## 현재 상태
| | |
|---|---|
| iOS | **1.0.3 Ready for Distribution** (라이브 안전판, 1.0.4 생성가능) |
| DB | **3,893** 카드 (53장 전부 LIVE) |
| 스캐너 | **3,889 / 57,100** (4장 보류) |
| 작업 브랜치 | `rescue/prod-baseline-20260616` (가격/스캐너/어드민 작업 여기) |
| 어드민 | 계수 표시버그 배포 완료 |

★ **DB 3,893 / scanner 3,889 / 57,100** — **차이 4장 = 오류 아님 = 명시적 스캔 보류목록**(`scanner/scanner_excluded_cards.json`). 보류 4장도 **DB·검색·상세·이미지·가격 정상, 스캔만 미지원**. ★**실기기 신규카드 샘플 스캔 = 사용자 확인 대기**(MASTER_FLOW Phase 0 미완).

## 다음 (MASTER_FLOW Step 1)
- **UI/UX·게시판 통합**: post-launch-front rebase → UI/UX dev통합(**게시판 목업 nav 노출차단**) → 게시판은 Step 2에서 백엔드+모더레이션 실구현 후 노출
- 더 조사: rebase 충돌 실범위 · 게시판 백엔드 실재(거의 없음 추정) · `rescue/prod-baseline`↔dev 정합
- ★**SNKRDUNK는 심사 대기 공백(Step 5)에**. 지금 시작 X. 기존 수집기 인수인계→운영화(매핑 불확실=staging만, 확정만 SNKRDUNK_SOLD_JP 승격).

## 롤백/백업
- prod 스캐너: `/opt/pokefolio/data/faiss/card_db.faiss.bak_pre49_*` (3840)
- prod 어드민: `/opt/pokefolio/app/admin/dist.bak_pricelabel_20260622_0632`
- 로컬 스캐너: `scanner/db/card_db.faiss.bak_pre53_*`(3840) · `.bak_3893all_*`(53전체)

## 이번 세션 산출 문서
- `docs/MASTER_FLOW.md` (전체 순서 ★)
- `docs/CARD_ADD_FLOW.md` (카드 추가 재사용 플레이북)
- `docs/SCANNER_HARDNEG_V2_ISSUE_20260622.md` (스캐너 v2 + 4장 보류)
- `scanner/scanner_excluded_cards.json` (보류 4장 allowlist)

## 세션 커밋 (`ops/handoff-20260622`)
- 커밋1 `fix(admin): mark rarity coefficients as reference-only` — admin/src/pages/Price.jsx
- 커밋2 `docs(ops): record gapfill runbook and 2026-06-22 handoff` — docs + scanner_excluded_cards.json
- (해시는 closeout 후 git log -2 로 기록 / 아래 채움)
- 운영 백업: admin `dist.bak_pricelabel_20260622_0632` · scanner `card_db.faiss.bak_pre49_20260622_0604`

## 다음 세션 시작 프롬프트 (새 대화에 그대로 붙여넣기)
```
포켓폴리오 프로젝트 작업을 이어간다. 먼저 아래 문서를 순서대로 읽고, 문서 내용과 실제 Git 상태를 대조해라.
1. docs/SESSION_HANDOFF_20260622.md
2. docs/MASTER_FLOW.md
3. docs/CARD_ADD_FLOW.md
4. docs/SCANNER_HARDNEG_V2_ISSUE_20260622.md

현재 확정 상태:
- iOS 1.0.3은 Ready for Distribution 상태
- DB 카드 3,893장 (신규 53장 모두 앱 검색·상세·이미지·가격 LIVE)
- 스캐너는 3,889장 / 57,100벡터, 신규 49장 스캔 지원
- 신규 4장(엘풍 ex SR·메타몽 V SSR·코바르온 AR·러브로스 V CSR)은 기존 카드 회귀 때문에 스캔만 보류
- 제외목록은 scanner/scanner_excluded_cards.json, 문제 4장은 hard-negative DINOv2 v2 통과 후 복귀
- 어드민 레어도 계수 표는 Spring 1차 참고값임이 표시되도록 수정·운영 배포 완료
- SNKRDUNK 운영화는 지금 시작하지 않음(UI/UX·게시판·Android 완성 후 양 스토어 심사 대기 기간에 기존 수집 파이프라인 운영화)
- 게시판은 현재 프론트 목업만 존재하고 백엔드는 없음

이번 세션 목표는 MASTER_FLOW Step 1이다: feat/post-launch-front의 UI/UX와 게시판 목업 현황을 정확히 분석하고 dev 통합 계획을 세운다.

현재 알려진 브랜치 상태: feat/post-launch-front는 dev 대비 23커밋 앞·19커밋 뒤, 게시판 목업 약 9커밋·UI/UX 약 14커밋, UI/UX가 게시판 목업 커밋 위에 쌓여 파일 단위로 얽혔을 가능성, 게시판 백엔드 및 feat/moderation-backend는 존재하지 않음.

작업 규칙:
1. 기존 브랜치를 바로 rebase하거나 force-push하지 마라.
2. 별도 worktree와 임시 integration 브랜치를 사용해라.
3. 먼저 보고: 정확한 merge-base / 양쪽 커밋 목록·파일 변경 범위 / UI/UX와 게시판 목업이 동시 수정한 파일 / 예상 충돌 파일 / UI/UX만 선반영 가능한지 / 게시판 목업 유지한 채 백엔드 신규 구현으로 이어가는 게 나은지.
4. 실제 merge/rebase/cherry-pick은 보고 후 사용자 승인 전까지 금지.
5. main/release 및 운영 서버 변경 금지.
6. 이번 세션에서 SNKRDUNK, 가격 v8, 스캐너 v2 작업을 시작하지 마라.

첫 응답은 문서와 Git 상태가 일치하는지 확인한 결과와, 가장 안전한 통합 전략만 보고해라.
```
