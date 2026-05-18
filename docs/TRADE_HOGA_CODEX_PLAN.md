# 호가창 — 구현 설계 plan (Codex + 엔티티 확인 결과)

> 작성: 2026-05-18 13:47
> UX 기준 문서: `docs/TRADE_HOGA_REFERENCE.md`
> 본 문서: **구현 설계 / API / DTO / tick / 위젯 / 채팅 흐름**
> 브랜치: `feat/trade-hoga-board`

---

## 0. 핵심 발견 — 기존 엔티티가 거의 다 갖춰져 있음

| 도메인 | 필요한 필드 | 현재 상태 |
|---|---|---|
| **BuyOrder** (BID) | card_id / bid_price / qty / card_status / grading_company / grade_value / memo | ✅ **모두 존재** — 추가 0 |
| **TradePost** (ASK) | card_id / asset_id / price / card_status / grading_company / grade_value / description | ✅ **모두 존재** (사용자 추측 100% — asset_id는 TradePost에만 있음) |
| **Asset** | card_status / grading_company / grade_value | ✅ 그레이딩 스코어까지 |
| **ChatRoom** | sale_listing_id / seller_user_id / buyer_user_id | ⚠️ **`sale_listing_id` NOT NULL** — BID side 채팅 흐름 별도 결정 필요 |
| **ChatService** | `getOrCreateRoom(saleListingId, buyerUserId)` | ✅ findOrCreate 패턴 이미 있음 |

→ **DB migration 거의 불필요**. 변경 후보:
1. ChatRoom 추가 결정 사항만 (sourceType OR sale_listing_id nullable OR 다른 방식)
2. 그 외는 그대로

---

## 1. 사용자 보강 8개 (구현 가이드)

| # | 보강 사항 | 적용 |
|---|---|---|
| 1 | UX 기준 = `TRADE_HOGA_REFERENCE.md` 유지 | ✅ |
| 2 | 구현 설계 = 본 문서로 분리 | ✅ |
| 3 | `asset_id`는 TradePost(ASK)에만 — BuyOrder X | ✅ 이미 그렇게 되어 있음 |
| 4 | BuyOrder에 asset_id 추가 X | ✅ |
| 5 | `hoga_status` → 기존 `card_status` 통일 | ✅ 기존 필드 그대로 사용 |
| 6 | tick 검증은 **등록 시점에 강제** (저장 단계에서 reject) | ✅ controller + DB constraint 둘 다 |
| 7 | 기존 엔티티 먼저 확인 (이 문서 §0) | ✅ 완료 |
| 8 | 확인 없이 DB 필드 추가 금지 | ✅ — DB 변경은 ChatRoom만 후보 |

---

## 2. 백엔드 API spec

### 2-1. 호가 요약 — `GET /api/cards/{cardId}/hoga`

**Query**:
| name | type | default | values |
|---|---|---|---|
| status | String | `RAW` | `RAW` / `PSA10` / `BRG` (1차) — CGC/PSA9/BGS 미지원 |
| limit | int | 5 | (보통 5) |

**Response DTO** (예시):
```json
{
  "cardId": "CRD_xxx",
  "status": "RAW",
  "tickUnit": 100000,
  "marketPrice": 43756830,
  "lowestAsk": 43800000,
  "highestBid": 43500000,
  "askCount": 12,
  "bidCount": 5,
  "asks": [
    {"price": 44000000, "count": 2, "barRatio": 0.50},
    {"price": 43900000, "count": 1, "barRatio": 0.25},
    {"price": 43800000, "count": 3, "barRatio": 0.75}
  ],
  "bids": [
    {"price": 43500000, "count": 1, "barRatio": 0.33},
    {"price": 43000000, "count": 2, "barRatio": 0.67},
    {"price": 42500000, "count": 1, "barRatio": 0.33}
  ]
}
```

**구현 위치**:
- 새 컨트롤러 `HogaController` (`back/src/main/java/com/fury/back/domain/trade/HogaController.java`)
- 또는 `CardController`에 endpoint 추가 — 시세도 그쪽이라 호가도 함께 가는 게 일관성. 추천 **CardController 확장**.

**Query 본질**:
- Asks: `TradePost`에서 `card_id` + `card_status` + (grading filter) + `status='ACTIVE'` → group by `price` → count
- Bids: `BuyOrder`에서 `card_id` + `card_status` + (grading filter) + `status='ACTIVE'` → group by `bid_price` → count
- 둘 다 동일 ServiceImpl에서 조합 → response 조립

**상태 필터 매핑 (PSA10은 복합 조건)**:
| UI status | DB WHERE |
|---|---|
| RAW | `card_status='RAW'` |
| PSA10 | `card_status='GRADED' AND grading_company='PSA' AND grade_value='10'` |
| PSA9 | `card_status='GRADED' AND grading_company='PSA' AND grade_value='9'` |
| BRG | `card_status='GRADED' AND grading_company='BRG'` (grade 무관 묶음) |
| ~~CGC~~ | **미지원** — 호가 등록 시 reject |

### 2-2. 가격별 등록자 — `GET /api/cards/{cardId}/hoga/{price}`

**Query**:
| name | type | required | values |
|---|---|---|---|
| status | String | ✅ | RAW / PSA10 / ... |
| side | String | ✅ | `ASK` / `BID` |

**Response DTO**:
```json
{
  "cardId": "CRD_xxx",
  "status": "RAW",
  "side": "ASK",
  "price": 43800000,
  "totalCount": 3,
  "listings": [
    {
      "userId": "user1",
      "nickname": "판매자A",
      "profileImageUrl": "...",
      "rating": 4.8,
      "memo": "민트급, 슬리브+토퍼",
      "createdAt": "2026-05-18T05:30:00",
      "assetId": "AST_xxx",
      "tradeId": "TRD_xxx",
      "tradeImageUrl": "..."
    },
    ...
  ]
}
```

- ASK: TradePost row 직접 + 판매자 평점 join
- BID: BuyOrder row 직접 + 구매자 평점 join (tradeId 없음)

### 2-3. 호가 등록 — 기존 endpoint 활용

| side | endpoint | 변경 |
|---|---|---|
| ASK | `POST /api/trades` 또는 `POST /api/trades/from-asset` | tick 검증 추가 |
| BID | `POST /api/buy-orders` | tick 검증 추가 |

새 endpoint 만들 필요 없음. 단 **server-side tick 검증 미들웨어** 추가:

```java
long tick = HogaTickResolver.resolve(price);
if (price % tick != 0) {
    throw new BadRequestException("호가 단위가 맞지 않습니다. " + tick + "원 단위로 입력해주세요.");
}
```

### 2-4. 채팅 자동 생성 — 기존 endpoint 활용

기존:
```
ChatService.getOrCreateRoom(saleListingId, buyerUserId)
```

→ **ASK side 채팅은 그대로 동작**. saleListingId = TradePost.tradeId.

**BID side 채팅 흐름 결정 필요 (사용자 결정 §6 참조).**

---

## 3. 동적 tick — `HogaTickResolver`

### Java
**위치**: `back/src/main/java/com/fury/back/domain/trade/HogaTickResolver.java`

```java
public final class HogaTickResolver {
    private HogaTickResolver() {}

    public static long resolve(long price) {
        if (price < 100_000L)    return 1_000L;
        if (price < 1_000_000L)  return 5_000L;
        if (price < 10_000_000L) return 10_000L;
        return 100_000L;
    }

    public static long floorToTick(long price) {
        long tick = resolve(price);
        return price / tick * tick;
    }

    public static long roundToTick(long price) {
        long tick = resolve(price);
        return Math.round((double) price / tick) * tick;
    }

    public static boolean isValidTick(long price) {
        return price > 0 && price % resolve(price) == 0;
    }
}
```

**사용처**:
- `POST /api/trades` controller — `isValidTick(price)` 검증, false면 reject
- `POST /api/buy-orders` controller — 동일
- `HogaController` 응답 `tickUnit` = `resolve(marketPrice)`

### Dart
**위치**: `front/lib/features/card/hoga/utils/hoga_tick.dart`

```dart
int hogaTick(int price) {
  if (price < 100000)    return 1000;
  if (price < 1000000)   return 5000;
  if (price < 10000000)  return 10000;
  return 100000;
}

int floorToHogaTick(int price) => (price ~/ hogaTick(price)) * hogaTick(price);
int roundToHogaTick(int price) {
  final tick = hogaTick(price);
  return ((price / tick).round()) * tick;
}
bool isValidHogaTick(int price) => price > 0 && price % hogaTick(price) == 0;
```

### 통일 보장
| 경계 | 결과 |
|---|---|
| 99,999 | 1,000 |
| 100,000 | 5,000 |
| 999,999 | 5,000 |
| 1,000,000 | 10,000 |
| 9,999,999 | 10,000 |
| 10,000,000 | 100,000 |

**테스트 케이스**: 양쪽 동일 — Java unit test + Dart test.

**서버가 source of truth**. Flutter tick은 UX용 (입력 보조 표시), 등록 시 서버 검증.

---

## 4. Flutter 위젯 구조

### 디렉토리
```
front/lib/features/card/hoga/
├── hoga_board.dart                       # 메인 위젯
├── hoga_status_chip_bar.dart             # RAW / PSA10 / BRG chip (1차)
├── hoga_row.dart                         # 단일 호가 row + 막대
├── hoga_pivot_row.dart                   # 현재가/midPrice 가운데 행
├── hoga_row_detail_sheet.dart            # 클릭 시 하단시트
├── hoga_register_sheet.dart              # 매도/매수 등록 모달
├── models/
│   ├── hoga_board_model.dart
│   └── hoga_listing_model.dart
├── services/
│   └── hoga_api.dart
└── utils/
    └── hoga_tick.dart
```

### 위젯 트리
```
HogaBoard (StatefulWidget)
├── HogaStatusChipBar (RAW / PSA10 / BRG)
├── HogaSummaryRow (lowest ask / highest bid / spread / count)
├── AskSection
│   └── HogaRow × 5 (with barGraph)
├── HogaPivotRow (midPrice + tickUnit)
└── BidSection
    └── HogaRow × 5 (with barGraph)
```

### State
```dart
class _HogaBoardState extends State<HogaBoard> {
  HogaStatus selectedStatus = HogaStatus.raw;
  final Map<HogaStatus, Future<HogaBoardModel>> _cache = {};

  Future<HogaBoardModel> _load(HogaStatus status) =>
      _cache.putIfAbsent(status, () => HogaApi.fetchBoard(widget.cardId, status));
}
```

### 색상
| side | color | hex 후보 |
|---|---|---|
| ASK (매도) | 파랑 | `Color(0xFF1E88E5)` 또는 앱 톤 매치 |
| BID (매수) | 초록 | `Color(0xFF10B981)` 또는 앱 톤 매치 |
| Red | ❌ 금지 | 경고/오류 색이라 거래에 부적합 |

### 호가 row 클릭 시
```dart
onTap: () => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  builder: (_) => HogaRowDetailSheet(
    cardId: cardId,
    status: status,
    side: side,
    price: price,
  ),
),
```

### card_detail_screen.dart 변경
- 기존 호가 영역 200~300줄 제거
- 한 줄로 대체: `HogaBoard(cardId: card.cardId)`

---

## 5. HogaRowDetailSheet (하단시트)

`showModalBottomSheet` + `DraggableScrollableSheet`:

| 속성 | 값 |
|---|---|
| initialChildSize | 0.55 |
| minChildSize | 0.35 |
| maxChildSize | 0.9 |

구조:
```
HogaRowDetailSheet
├── 드래그 핸들
├── 헤더 (side label / price / totalCount)
├── ListView
│   └── HogaListingTile × N
│       ├── 프로필 (사진 + 닉네임 + 평점)
│       ├── 상태 (RAW / PSA10 등)
│       ├── 메모
│       ├── 등록 시각 (상대시간)
│       └── [💬 채팅하기] 버튼
└── (선택) 고정 CTA "같은 가격에 매도 등록"
```

**채팅하기 클릭**:
- side=ASK → `ChatService.getOrCreateRoom(tradeId, buyerUserId=currentUser)` → 채팅방 진입
- side=BID → **§6 결정 사항**

---

## 6. ⚠️ 결정 필요 — BID side 채팅 흐름

**문제**: `ChatRoom.sale_listing_id`가 NOT NULL이라 BuyOrder만으로 ChatRoom 생성 불가.

**옵션**:

| 옵션 | 방법 | 1차 출시 적합? |
|---|---|---|
| **A (추천)** | 1차: BID 호가에서 채팅 X. **알림만**. 매수자가 "이 가격에 사겠다" 표시 → 보유자에게 알림 → 보유자가 자기 자산을 TradePost로 등록 → 매수자가 매도 호가에서 채팅 | ✅ 단순, DB 변경 0 |
| B | ChatRoom 모델 확장: `source_type` (TRADE / BUY_ORDER) + `sale_listing_id` nullable | 추가 작업, migration 필요 |
| C | BID 호가에서 "이 매수자와 거래" → TradePost 임시 생성 (status='OFFER_FROM_BUYORDER') → 그것으로 채팅 | 흐름 부자연스러움 |
| D | BuyOrderChatRoom 별도 도메인 | 도메인 복잡, 비추천 |

**추천: 옵션 A**. 1차 출시 단순화. 비대칭이지만 사용자 흐름은 자연스러움:
- 매수 호가 = "이 가격에 사겠다 표시" (시장 신호)
- 매도 호가 = "이 가격에 팔겠다 매물" (실제 거래)
- 매수자가 직접 채팅 시작은 매도 호가에서만

기존 `cb4ee678 feat(notification): BuyOrder 등록 시 카드 보유자에게 자동 알림` commit이 이미 알림 흐름 구현 완료. 그대로 활용.

**향후 (Phase 2 이후)**: 옵션 B로 확장 가능.

---

## 7. 호가 등록 모달 — `HogaRegisterSheet`

### UI
```
[탭] 판매하기 / 매수하기
[상태] RAW / PSA10 / BRG chip (1차) — CGC/PSA9 미지원
[가격] 입력 (동적 tick 안내: "현재 5,000원 단위")
  → 입력 즉시 roundToHogaTick으로 미리보기
[메모] (선택)
[사진] (선택, ASK만)
[등록]
```

### 가격 입력 검증
```dart
final price = roundToHogaTick(int.parse(input));
final tick = hogaTick(price);
// "120,300원 → 120,000원으로 자동 조정됩니다" 표시
```

### ASK 등록 시 자산 선택
**메모리 `feedback_scanner_only_asset_entry.md`**: 자산 등록은 스캐너 단일 게이트. 즉 매도 호가도 **자산 selector**가 스캐너로 잡힌 자산만 표시.

흐름:
1. 매도 호가 등록 → 자산 selector (Asset 리스트에서 선택)
2. 자산 없으면 → "먼저 자산 등록" CTA → 스캐너로 유도
3. 선택한 자산의 card_status/grading_company/grade_value 자동 채움
4. 가격 + 메모만 입력 후 등록

### BID 등록 시
1. 매수 호가 등록 → 카드 선택 (이미 카드 상세에 있으면 자동)
2. 상태 chip 선택 (RAW / PSA10 / ...)
3. 가격 + 수량 + 메모

---

## 8. 1차 출시 scope 명확화

### In scope (1차 출시)
- [x] 카드별 호가 조회 (RAW + 감정등급별)
- [x] 매도 5 + 매수 5 호가창
- [x] 호가 row 클릭 → 하단시트 등록자 리스트
- [x] ASK 호가 클릭 → 채팅 자동 생성 (기존 `getOrCreateRoom` 활용)
- [x] BID 호가 = 매수 의사 표시 + 알림 (기존 commit `cb4ee678` 활용)
- [x] 동적 tick 등록 검증 (서버 + 클라이언트)
- [x] 호가 0건 empty state CTA
- [x] 색상: 매도 파랑 / 매수 초록
- [x] card_detail_screen.dart에서 HogaBoard 위젯 분리

### Out of scope (Phase 2 이후)
- 결제 / 에스크로 / 정산
- 즉시 구매 / 즉시 판매
- WebSocket 실시간 호가 갱신
- BID side 직접 채팅 (옵션 B/C)
- 호가 자동 매칭 엔진
- 거래 완료 → APP_TRADE snapshot 자동 INSERT (출시 작업 1번 후반부)
- PSA 9 미만 세분화 (8, 7 등)

---

## 9. 작업 순서 (Phase B~G)

| Phase | 작업 | 예상 시간 |
|---|---|---|
| **B** | HogaTickResolver Java + DTO + HogaController endpoint 2개 | 1.5h |
| **C** | Flutter `hoga/` 디렉토리 + 모델 + API client + utils (hoga_tick.dart) | 1h |
| **D** | HogaBoard 위젯 (status chip + ask/bid section + row + bar graph) | 2h |
| **E** | HogaRowDetailSheet (하단시트 + 등록자 리스트) | 1h |
| **F** | HogaRegisterSheet (매도/매수 등록 모달 + 자산 selector ASK / 카드 BID) | 2h |
| **G** | ASK 채팅 자동 생성 연결 + tick 등록 검증 + empty state CTA | 1h |
| **H** | Codex 코드리뷰 + 통합 테스트 + commit | 1h |

총 **약 9.5시간** (하루치)

---

## 10. 잠재 함정 / 주의 (Codex + 사용자 보강)

1. **PSA10은 복합 조건** — UI enum은 `PSA10`이지만 DB WHERE는 `card_status='GRADED' AND grading_company='PSA' AND grade_value='10'`. 필터 함수 한 곳에 집중.

2. **BRG는 grade 무관 묶음** — 회사 단위만. 세분화하면 chip 수 폭증. CGC는 1차 미지원.

3. **tick 검증은 서버가 source of truth** — Flutter는 UX 보조. POST endpoint에서 무조건 검증.

4. **TradePost vs BuyOrder 데이터 다른 도메인** — HogaController에서 service layer adapter로 통합. side 분기 처리 위치는 service 한 곳.

5. **ChatRoom.sale_listing_id NOT NULL** — BID 채팅 흐름 옵션 A 선택 (§6).

6. **자산 등록 단일 게이트** — ASK 호가 등록 시 자산 selector. 자산 없는 사용자는 스캐너로 유도 (메모리 `feedback_scanner_only_asset_entry.md`).

7. **기존 호가 데이터 마이그레이션** — 현재 DB의 buy_orders 4건은 모두 신규 tick 단위로 등록됐을 가능성. 단 수동 점검 후 진행. 위반 row 있으면 PENDING 처리 또는 사용자 보정 알림.

8. **카드 상세 sticky 시세 + HogaBoard 위치** — 기존 카드 상세 헤더(`feat(card-detail): 호가창 상단 헤더 — 대표 시세 + 매도/매수 카운트`)와 새 HogaBoard 충돌 X 확인. 통합 또는 새 디자인 결정.

---

## 11. 사용자 결정 (Phase B 시작 전)

| # | 결정 | 후보 |
|---|---|---|
| 1 | **BID 채팅 옵션** | A (1차 알림만) / B (DB 확장) / C (임시 TradePost) |
| 2 | **HogaController 위치** | `domain/trade/HogaController` 신규 / `domain/card/CardController`에 메서드 추가 |
| 3 | **기존 카드 상세 호가 헤더** | 유지 + HogaBoard 통합 / 헤더 제거하고 HogaBoard로 전부 대체 |
| 4 | **1차 chip 결정** | **확정: RAW / PSA10 / BRG** (CGC 미지원, PSA9 1차 제외) |

추천 (Claude):
1. **A** — 1차 단순, 비대칭 OK
2. **신규 HogaController** — 도메인 분리 깨끗
3. **헤더 + HogaBoard 통합 (Sticky)** — 위쪽 헤더(대표 시세) + 아래 호가창
4. **확정** — 1차 RAW + PSA10 + BRG만 (CGC/PSA9/BGS 미지원)

---

> 이 4개 결정 받으면 Phase B (백엔드) 즉시 시작 가능.
