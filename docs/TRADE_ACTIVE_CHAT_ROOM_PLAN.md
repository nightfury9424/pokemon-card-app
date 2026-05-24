# 거래중 상대 지정 모델 — 다음 mini-cycle plan

작성: 2026-05-24 (Phase 1 hotfix#7 시점, scope 분리)

## 배경

hotfix#7 진입 시 두 가지가 한 cycle 안에 있었음:
- (A) 현재 버그 3종 — 화면 전환 dim / route stack 정합 / 거래완료 옵션 누락
- (B) 거래중 상대 지정 모델 — `예약중` 라벨 모호성 + 누구와 거래중인지 미지정

사용자 결정: **A만 hotfix#7로 처리 / B는 다음 mini-cycle로 분리**. 이유:
- A는 사용자 직접 본 회귀, 즉시 fix 필요
- B는 모델 확장 (DB + API + UX 변경) — A와 섞으면 회귀 추적 어려움

본 문서는 B의 결정/scope를 기록 — 다음 mini-cycle 진입 시 그대로 참조.

## 사용자 확정 정책

1. **UI label 변경**: "예약 중" → "거래 중" (DB enum `RESERVED` 유지, UI 라벨만 변경)
2. **거래중 = 상대 지정 필수** — 단순 status 변경으로는 부족
3. **DB 컬럼**: `trade_posts.active_chat_room_id` 추가 (chat 기반이 자연 — `trading_with_user_id` 대비)
4. **UX flow**: 상태 sheet → "거래중" 선택 → 두 번째 sheet "거래 상대 선택" → chat 방 list → 선택 → 거래중 변경
5. **선택된 상대만 채팅 가능**, 비선택 상대는 입력 비활성 + 안내 "다른 사용자와 거래가 진행 중입니다."
6. **거래중 → 판매중 복귀**: active_chat_room_id clear, 모든 상대 다시 채팅 가능
7. **거래완료 final**: COMPLETED 후 상태 변경 X (Codex 사전 검토 #7)

## Codex 사전 검토 결정 8개 (사이클 진입 시 그대로 적용)

1. **Route stack** → C — Sheet는 tradeId만 반환, push는 parent (hotfix#7에서 이미 적용)
2. **dim overlay** → B — `_chatLoading` inline spinner only (hotfix#7에서 잔여 확인)
3. **마이그레이션** → B — 컬럼 추가 + backfill 2단계 (D-7 validate 리스크 차단)
4. **상대 선택 UI** → A — 상태 sheet → 두 번째 sheet (발견성 최고)
5. **데이터 source** → B — 신규 `GET /api/trades/{id}/chat-partners` (서버가 후보 확정, 권한/숨김 누수 차단)
6. **거래중→판매중 안내** → B — visible SYSTEM 메시지 "판매자가 다시 거래 가능 상태로 변경했습니다."
7. **거래완료 이후** → A — final (호가/채팅/자산 정합)
8. **getConversationState 확장** → B — 신규 `isExcludedFromActiveTrade` 필드 (원인 분리)

## 예상 변경 (8~10 파일)

### Backend (5~6)
- `back/sql/trade_active_chat_room_migration.sql` — `ALTER TABLE trade_posts ADD COLUMN active_chat_room_id VARCHAR(50)` + FK `chat_rooms`
- `TradePost.java` — `activeChatRoomId` 필드 + getter
- `TradeServiceImpl.updateStatus(tradeId, userId, status, chatRoomId?)` — RESERVED 시 chatRoomId 인자 필수
- `TradeController` — status 변경 API에 chatRoomId optional 추가
- `TradeController` 신규 `GET /api/trades/{id}/chat-partners` — 후보 list (saleListingId 기반 ChatRoom + 각 buyer 정보)
- `ChatServiceImpl.getConversationState` — `isExcludedFromActiveTrade` 추가 (activeChatRoomId != null && roomId != activeChatRoomId)
- `ChatServiceImpl.sendMessage` — 비선택 상대 가드 (`requireNotExcludedFromActiveTrade`)
- `ConversationStateDto` — 필드 추가
- `ChatServiceImpl.broadcastTradeStatusChanged` — 거래중→판매중 시 SYSTEM "판매자가 다시 거래 가능 상태로 변경했습니다."

### Frontend (3~4)
- `trade_detail_screen.dart _showStatusSheet`:
  - "예약 중" 라벨 → "거래 중"
  - "거래중" 선택 시 바로 status 변경 X → 두 번째 sheet 호출
- 신규 `lib/features/trade/trade_partner_select_sheet.dart` — chat 방 list + 선택
- `chat_room_screen.dart`:
  - banner/입력 비활성화 로직에 `isExcludedFromActiveTrade` 분기 추가
  - 라벨 "예약 중" → "거래 중" (chip)
- 호가 list "예약 중" chip 라벨 변경 (`hoga_listing_response`)

## 검증 시나리오 (다음 cycle)

1. 판매중 → 거래중 → 상대 선택 sheet → A 선택 → status RESERVED + active_chat_room_id=A방
2. B/C 채팅방: 입력 비활성 + banner "다른 사용자와 거래가 진행 중입니다."
3. A 채팅방: 정상 (입력 활성)
4. 거래중 → 판매중 복귀: active_chat_room_id NULL + B/C 채팅방 banner 제거 + 입력 활성 + SYSTEM "판매자가 다시 거래 가능 상태로 변경했습니다."
5. 거래중 → 거래완료: COMPLETED + 호가 제외 + 채팅 정책 결정 (선택된 상대만 채팅 가능 OR 모두 비활성)
6. 거래완료 → 상태 변경 시도: 차단 (final)

## D-7 위험 정리

- 마이그레이션 BACKFILL: 기존 RESERVED 거래는 active_chat_room_id NULL → 처리 정책 결정 필요 (기존 채팅방 1개면 자동 set OR 그대로 NULL)
- `ChatServiceImpl.sendMessage` 가드 추가 → 회귀 위험 (참여자 검증 + 차단 + 나감 + 거래중 비선택 = 4개 가드)
- 거래완료 이후 active_chat_room_id 처리 — 선택된 상대와 채팅 계속 가능 vs 모두 비활성 (정책 결정 필요)
- `/api/trades/{id}/chat-partners` 권한 — 판매자만 호출 가능 + 차단된 user 제외

## 진입 신호

본 plan은 hotfix#7 통과 후 사용자 GO 신호 받으면 진입. Codex 사전 검토 결정 8개 이미 확보 → 사전 검토 skip 가능, 즉시 구현 진입.
