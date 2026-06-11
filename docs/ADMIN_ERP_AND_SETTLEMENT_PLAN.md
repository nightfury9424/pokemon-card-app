# 관리자 ERP + 실거래가(Settlement) 데이터모델 + 시세 진화 — 계획

> 2026-06-10. Codex 토론(세션 019eaefd) + 종합. **구현 = App Review 승인 후 1.0.1+** (지금 심사 대기 중).
> 단, 관리자 React 프론트는 심사 무관이라 선작업 가능 (§4).

## 1. 실거래가(Settlement) 데이터모델 — "둘 다 저장 + 관리자 가시성"
**현재**: `trade_settlements`(trade_id, user_id, role[BUYER/SELLER], card_id, reported_price) + `POST /api/trades/{id}/settlement` & `/buy-order/{id}/settlement`, COMPLETED만, **유저 입력 경로만 있음**. **관리자 조회/입력 엔드포인트 없음 → 아무 데서도 안 보임.**

**목표**: 게시가 + 실거래가 둘 다 저장하고 관리자가 본다.
- **`posted_price_snapshot`**: 완료 시점 게시가를 **immutable 스냅샷** (가변 게시가로 사후 조작 방지 — Codex 지적)
- **`reported_price`**: 역할별 유저 입력
- **출처/신뢰 라벨** (관리자가 데이터 품질 구분 + 모델 ingest 게이트):

| 라벨 | 의미 | 모델 ingest |
|---|---|---|
| `CONFIRMED_BOTH` | 양쪽 입력·일치 | ✅ 최상 |
| `ADMIN_ENTERED` | 관리자가 글·채팅 보고 유추 입력 | ✅ 중(검토됨) |
| `CONFIRMED_SINGLE` | 한쪽만 입력 | ✅ 저(필터링) |
| `DISPUTED` | 양쪽 값 다름 | ❌ 해소 전 제외 |
| `POSTED_DEFAULT_BID` | 미입력→매수 bid 폴백 | ❌ |
| `POSTED_DEFAULT_ASK` | 미입력→판매 ask 폴백(상향편향) | ❌ |

- **trade_id 단위 집계** (참가자 row 이중집계 방지)
- **UX**: 게시가 prefill + "이 가격 맞아요?" 확인. silent default는 **유예(24~72h) 후**만, POSTED_DEFAULT 라벨.
- **조작방지**: `HELD_FOR_REVIEW`, 유저 신뢰점수, 아웃라이어/재거래/동일기기·신규계정 risk-score.

## 2. 시세 모델 — 현재 "수집만 / 미적용" (freeze 유지)
- 현재 v6 = **JP×비율 + chase floor + EN→JP 브릿지 + DAANGN obs + MANUAL_FLOOR** → **APP_TRADE(정산 실거래가) 공식 미포함.**
- 즉 **정산 데이터는 테이블에 쌓이기만, 시세엔 안 들어감.** (확인됨, freeze 정책)
- **진화(데이터 플라이휠)**: 전체 flip 아님 → **카드별 졸업**(관측치 수·최신성·일치도 임계) → CONFIRMED/ADMIN_ENTERED 위주 ingest → §3 P3 관측성으로 정확도 측정(백테스트) → **가드 강화**(sanity → 조작방지) → 점진 자동.
- **unfreeze = 날짜 아님, 지표+가드+승인+롤백체인 게이트.**
- ingest 규칙: `CONFIRMED_BOTH` + 필터된 `CONFIRMED_SINGLE` + `ADMIN_ENTERED`(중신뢰). `POSTED_DEFAULT_*`/`DISPUTED` 제외.

## 3. 관리자 ERP — 운영자 작업대 (예쁜 대시보드 아님)
- **P0: 모더레이션 워크벤치** — 통합 신고 큐 + **SLA**(createdAt/dueAt/age/잔여/breach) + **증거 drawer**(채팅·거래·유저·이력) + **일괄조치**(기각/경고/삭제/정지/assign) + **결정 모달**(사유템플릿+내부메모+유저메시지+audit) + 지표(open/<4h/breach/응답중앙·p95/재범). ★Apple 가이드 원문은 "timely"지 24h 명시 아님 → **우리 24h는 회신에서 한 자체 SLA** → 타임스탬프+breach추적+audit 必.
- **P1: 유저·신뢰** — 경고/정지/신고이력/거래/이의신청/admin action history + 재범탐지
- **P2: 거래운영** — 게시가/실거래가/라벨 **가시성** + **관리자 임의 입력(ADMIN_ENTERED + admin_actions audit)** + 정산 미완 거래 큐 + 의심정산 신호
- **P3: 가격·데이터품질** — 카드별 APP_TRADE 커버리지 / CONFIRMED·DEFAULT·DISPUTED 카운트 / 아웃라이어 큐 / 정확도(모델가 vs 이후 실거래) — **관찰·게이트만, 모델 freeze**
- **P4: 임원 대시보드** — 큐 건전성/SLA/안전/거래량/커버리지 요약 (워크플로우 갖춘 후)
- **컴포넌트**: 공용 `AdminDataTable`(서버 페이지네이션/필터/정렬/체크박스/sticky 액션바/로딩·빈·에러) + 필요시 TanStack Table + Recharts 유지 + `SlaBadge`/`StatusBadge`/`BulkActionBar`/`EvidenceDrawer`/`DecisionModal`/`UserRiskPanel`/`AuditTimeline`. **전면 재작성 X, 모듈별 점진.**

## 4. 심사 중 작업 안전성
- **관리자 React 프론트** = 심사 대상 아님(별도 앱, IPA 무관) → **자유 작업, 심사 영향 0.**
- **관리자 전용 백엔드 엔드포인트(읽기)** = AdminAllowlistFilter 게이트(앱 미사용) → 심사 리스크 낮음. 단 **prod 배포는 디시플린**(백업+diff+롤백).
- **settlement 데이터모델 변경(컬럼 추가/마이그레이션)** = trade 도메인 + DB 마이그 → 실질 변경, **가급적 승인 후**.

## 큰 리스크 (Codex)
- silent posted-default가 최강 시그널(APP_TRADE) 오염 → 라벨 필수.
- 참가자별 row 이중집계 → trade_id 단위.
- 가변 게시가 → 완료시점 스냅샷.
- 24h SLA = UI 아니라 타임스탬프+breach+audit+운영자 책임.
- 일괄 모더레이션은 강한 audit/사유 캡처 없으면 이의신청 리스크.
- ERP 전면 재작성 sprawl 주의 → 모더레이션 큐부터.
