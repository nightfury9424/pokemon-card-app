# Card Detail Screen Redesign

> 작성일: 2026-05-11
> 목적: 내일 1순위 작업인 카드 상세 화면의 "내 자산" vs "시세" 분리 구현 기준 문서

---

## Executive Summary

추천안은 **Option A: Hard Tabs (`시세` | `내 자산`) + Sliver 카드 이미지 히어로**다. 구현은 `NestedScrollView` + `SliverAppBar` + `TabBar` + `TabBarView`가 가장 맞다.

다만 탭 순서는 사용자 맥락에 따라 바꾼다.

- **비소유자 기본 탭: `시세`**. 가격, 차트, 거래 흐름을 보러 들어온다.
- **소유자 기본 탭: `내 자산`**. 구매가 대비 현재가, 손익, 등급, 판매 CTA가 먼저 필요하다.
- 탭은 항상 둘 다 유지한다. 판매를 고민하는 사용자는 `내 자산`과 `시세`를 빠르게 오가야 한다.

이 결론은 현재 코드 구조와 잘 맞는다. [card_detail_screen.dart](/Users/fury/pokemon-card-app/front/lib/features/card/card_detail_screen.dart)는 이미 상세 진입 시 `GET /api/cards/{cardId}`, `GET /api/prices/cards/{cardId}/price-summary`, `GET /api/trades?cardId=...`를 병렬 호출하고, `myAsset`이 있으면 `GET /api/assets/{assetId}`로 최신 자산을 보강한다. 문제는 이 데이터가 한 화면의 `SingleChildScrollView` 안에 `카드 히어로 -> 자산 등급 -> 시세 -> 호가 -> 판매 목록` 순서로 섞여 있어, 소유자가 원하는 손익 정보와 비소유자가 원하는 시장 정보가 서로 묻힌다는 점이다.

**직접 지원되는 코드 근거**

- 카드 상세는 현재 `SingleChildScrollView` 단일 컬럼이다: `_buildCardHero`, `_buildAssetGradeSection`, `_buildPriceSection`, `_buildOrderBookSection`, `_buildListingsSection`, `_buildSellBar`.
- 가격 요약은 상세 전용 엔드포인트가 이미 있다: `GET /api/prices/cards/{cardId}/price-summary`.
- 자산 필드는 `quantity`, `purchasePrice`, `cardStatus`, `gradingCompany`, `gradeValue`, `certNumber`, `estimatedGrade`, 분석 점수, `isSelling`, `activeTradeId`가 DTO로 내려온다.
- 자산 이미지 목록은 `GET /api/assets/{assetId}/images`가 `FRONT`/`BACK`/`SLAB` 이미지를 반환할 수 있다.
- 판매 목록은 현재 코드가 `GET /api/trades?cardId={cardId}&page=0&size=20`을 쓰고 있으며, `TradePostDto`에 가격, 상태, 등급, 판매자, 생성일이 있다.

**디자인 의견**

- 카드 이미지는 TCG 앱처럼 히어로로 크게 둔다. 포켓몬 카드는 가격표 이전에 수집품이며, 이미지가 신뢰와 소장 욕구를 만든다.
- Toss Securities식 하단 자산 플로팅 카드는 이번 1순위에는 과하다. 현재 `bottomNavigationBar`가 이미 판매 CTA를 담당하므로, 자산 정보를 별도 floating drawer로 만들면 내일 구현 범위가 커진다.
- `시세`와 `내 자산`의 하드 탭은 가장 구현 리스크가 낮고, 데이터 소스도 지금 화면에 이미 모여 있다.

---

## Reference Patterns

이 섹션은 구현 명세가 아니라 디자인 참고다. 외부 앱 레퍼런스는 2026-05-11 기준 공개 도움말/검색 결과와 사용자 제공 패턴을 바탕으로 정리했다.

### Robinhood

Robinhood의 주식 상세는 차트를 가장 먼저 보여주고, 보유 중이면 포지션 섹션에서 shares, market value, average cost, portfolio diversity, today's return, total return을 보여준다. 공식 도움말도 상세 페이지가 차트와 포지션/수익 정보를 중심으로 구성된다고 설명한다.

PokeFolio 적용:

- 차트와 현재가는 `시세` 탭의 최상단에 둔다.
- `내 자산` 탭은 Robinhood의 Position 섹션처럼 보유 수량, 현재 평가액, 구매가, 총 손익, 수익률을 한 화면 첫 카드에 압축한다.

참고: https://robinhood.com/us/en/support/articles/viewing-stock-detail-pages/

### Coinbase

Coinbase는 자산 가격 페이지에서 price chart, market cap, volume, supply, all-time high 같은 시장 지표를 먼저 보여준다. 포트폴리오 쪽에서는 gains/losses와 open positions를 분리해 관리한다.

PokeFolio 적용:

- 비소유자는 자산 정보가 없으므로 `시세`를 default로 둔다.
- "포트폴리오/보유" 개념은 시장 정보와 같은 화면에 있더라도 별도 탭으로 독립시킨다.

참고: https://help.coinbase.com/en/coinbase/getting-started/crypto-education/price-page-information-

### Toss Securities

사용자 제공 패턴: `종목정보 | 차트 | 재무 | 공시 | 뉴스` 탭, 보유 주식 카드는 별도 persistent card로 노출.

PokeFolio 적용:

- 탭은 정보 구조를 정리하는 데 강하다.
- 하지만 PokeFolio는 "내 자산 vs 시세"가 내일 1순위 요구사항이므로, Toss처럼 보유 카드만 하단에 독립시키기보다 탭으로 명확히 분리한다.
- 판매 CTA는 기존 `bottomNavigationBar`를 유지해 Toss의 persistent action 역할만 가져온다.

### TCGplayer

카드 상세에서 카드 이미지, listings, market price, price history, condition별 가격을 강하게 노출한다. 카드 게임 앱에서는 이미지가 금융 앱의 종목명/로고보다 훨씬 중요한 hero asset이다.

PokeFolio 적용:

- `SliverAppBar.expandedHeight` 안에 카드 이미지와 이름/레어도/번호를 넣는다.
- 가격 탭에는 "최근 판매/판매중"을 바로 연결한다.

참고: https://www.tcgplayer.com/product/515537/

### PSA / PWCC / Graded Collecting

PSA 가격 가이드는 등급별 가격을 기준으로 탐색한다. PSA 10과 raw는 같은 카드라도 다른 시장으로 봐야 한다.

PokeFolio 적용:

- `cardStatus == GRADED`이면 히어로와 `내 자산` 탭 모두에 `PSA 10`, `BGS 9.5`, `CGC 10` 같은 grade badge를 크게 표시한다.
- `시세` 탭의 EN/JP 가격 chip은 현재 코드처럼 `RAW`, `PSA 10`, `PSA 9`를 유지한다.
- KO 예상가는 현재 백엔드 DTO상 RAW 중심이다. graded KO 가격은 **TBD**로 명시한다.

참고: https://www.psacard.com/priceguide/

---

## Option Analysis

### Option A: Hard Tabs (`내 자산` | `시세`)

추천. 요구사항과 가장 직접적으로 맞고, 현재 코드의 `_buildAssetGradeSection`, `_buildPriceSection`, `_buildOrderBookSection`, `_buildListingsSection`를 탭 child로 재배치하기 쉽다.

장점:

- 사용자에게 정보 구조가 명확하다.
- `내 자산` 탭에서 손익 계산을 크게 보여줄 수 있다.
- `시세` 탭에서 KO/EN/JP 차트와 판매 목록을 방해 없이 보여준다.
- 기존 `bottomNavigationBar` 판매 CTA와 충돌이 적다.

단점:

- 소유자가 `내 자산` 탭에 있으면 차트가 가려진다.

보완:

- `내 자산` 탭 첫 카드 안에 `현재 시장가`와 `손익`을 크게 넣고, `시세 보기` 작은 CTA로 탭 전환을 제공한다.
- 히어로 collapsed 영역에는 `KO 대표가`를 한 줄로 노출한다. 이건 디자인 의견이며, 기존 코드에는 아직 없다.

### Option B: Sticky Sections

비추천. 카드 이미지 -> 가격 -> 내 자산 -> 시세 상세 순서의 단일 스크롤은 모든 정보가 보이지만, 현재 화면의 문제가 "섞여 있음"이라는 점을 해결하지 못한다.

장점:

- 탭 이동 없이 모든 것을 볼 수 있다.

단점:

- 소유자에게 긴 스크롤을 강요한다.
- 비소유자에게 빈 자산 section 처리가 필요하다.
- 현재 `SingleChildScrollView`의 복잡도를 유지한 채 섹션만 늘리는 결과가 된다.

### Option C: Toss Securities Hybrid

2차 개선 후보. 시세/카드정보 탭과 하단 `내 자산` floating card는 금융 앱 패턴으로 좋지만, 내일 목표인 "내 자산 vs 시세 탭 분리"와 다르다.

장점:

- 시세를 항상 중심에 둔다.
- 보유 정보가 action 가까이에 있다.

단점:

- 하단 판매 bar와 자산 card가 경쟁한다.
- graded image, app grading result, multiple copies 같은 정보는 floating card에 담기 어렵다.

### Option D: Two Separate Screens

비추천. 현재도 자산 화면에서 상세로 들어올 때 `extra: {'myAsset': asset}`을 넘기고 있지만, 상세 화면 자체가 시세/자산을 섞어 처리한다. 화면을 둘로 나누면 판매 의사결정 사용자가 두 화면을 왕복해야 한다.

---

## Final Layout Spec

### Overall Structure

```text
Scaffold
  backgroundColor: AppColors.bg
  body: DefaultTabController or explicit TabController
    NestedScrollView
      headerSliverBuilder
        SliverAppBar
          pinned: true
          expandedHeight: 360 mobile / 420 large
          collapsedHeight: toolbar default
          flexibleSpace: card image hero
          bottom: PreferredSize(TabBar)
      body: TabBarView
        MarketTab
        AssetTab
  bottomNavigationBar
    owner only: grade/sell actions
```

### Measurements

- Screen horizontal padding inside tab content: `16`.
- Section gap: `16`.
- Card section border radius: `12` or `16` only where existing code already uses it. Existing app uses `16`; keep it for consistency.
- Hero expanded height: `360` on phone. Current hero image is `220 x 308`; new hero should use `min(screenWidth * 0.62, 260)` width and fixed card aspect `100 / 140`.
- Hero image aspect ratio: `100 / 140` (`width / height = 0.714`). Use `AspectRatio(aspectRatio: 100 / 140)`.
- TabBar height: default `48`.
- Chart height: keep current `220`.
- Bottom sell bar height: current padding roughly `84`; keep owner-only `bottomNavigationBar` and add tab body bottom padding `96`.
- Badge radius: `6`.
- Price hero font:
  - KO current: `28-32`, weight `800`.
  - P&L: `16`, weight `700`.
  - labels: `12`, `AppColors.textSecondary`.

### Header / Hero

Order inside expanded hero:

1. Card image centered, large.
2. Overlay top-right: rarity badge using `AppColors.rarityColor(rarity)`.
3. Overlay top-left if owned and graded: grade badge (`PSA 10`, `BGS 9.5`, `CGC 10`) with `AppColors.gold`.
4. Bottom gradient scrim.
5. Card name, `collectionNumber`, product line.
6. Optional compact KO price line: `KO 추정가 32,920원` if `_priceSummary.ko.mid` exists.

Current fields:

- `name`: `CardDto.name` or asset `card.name`.
- `rarityCode`: `CardDto.rarityCode` or asset `card.rarityCode`.
- `collectionNumber`: `CardDto.collectionNumber`.
- `productName`, `seriesName`, `productType`: `CardDto` only from card detail endpoint.
- image: `resolveCardImageUrl(data)` and `resolveCdnImageUrl(data)`.

### Tabs

Use exactly two primary tabs:

1. `시세`
2. `내 자산`

Reason for `시세` first: browsing is the universal case, and non-owner default is index 0. For owners, set initial index to `1`. This keeps tab order stable across user types while honoring owner intent.

Optional later tab: `거래`. For tomorrow, keep recent listings inside `시세` to avoid a third tab. Current `_buildListingsSection` and `_buildOrderBookSection` are market context, not asset context.

---

## Tab Content Breakdown

### `내 자산` Tab

For owned cards, show these fields in order.

#### 1. Position Summary Card

Fields:

- `보유 수량`: `_localAsset['quantity']` from `AssetDto.quantity`. Default `1`.
- `구매가`: `_localAsset['purchasePrice']` from `AssetDto.purchasePrice`. If null, show `미입력`.
- `현재 시장가`: `_priceSummary['ko']['mid']` from `CardPriceSummaryDto.ko.mid`. If null, fallback to `_cardDetail['koEstimatedPrice']` only when present. If both absent, show `시세 없음`.
- `평가금액`: `현재 시장가 * quantity`. Computed client-side.
- `손익`: `(현재 시장가 - purchasePrice) * quantity`. Computed client-side. Only if purchasePrice and current price exist.
- `수익률`: `(현재 시장가 - purchasePrice) / purchasePrice * 100`. Computed client-side. Only if purchasePrice > 0.

Supported by code:

- `asset_screen.dart` already computes market value from `/api/prices/cards/{cardId}/ko-price` and portfolio return from `purchasePrice`.
- `card_detail_screen.dart` already has `_priceSummary.ko.mid`.

Display:

```text
내 자산
평가금액 98,760원
+38,760원 (+64.6%)

보유 수량 3장
구매가 20,000원 / 장
현재가 32,920원 / 장
```

Important: If `quantity > 1`, label purchase/current prices as per-copy. Current data model stores one `purchasePrice` on an asset row, not per-lot history. Treat it as per-card purchase price because existing portfolio code compares one `purchasePrice` to one market price and does not multiply purchase by quantity. This is an implementation concern to fix later.

#### 2. Card Status / Grade Card

Fields:

- `카드 상태`: `_localAsset['cardStatus']`, values `RAW` / `GRADED`.
- `감정사`: `_localAsset['gradingCompany']`, current add flow allows `PSA`, `BGS`, `CGC`; one sell sheet currently uses `BRG`, likely typo/TBD.
- `등급`: `_localAsset['gradeValue']`.
- `인증번호`: `_localAsset['certNumber']`.

If `cardStatus == GRADED`:

- Show grade badge large: `PSA 10`.
- Show cert number if present.
- Show slab image if available from `GET /api/assets/{assetId}/images` where `imageType == 'SLAB'`.

If `cardStatus == RAW`:

- Show `RAW`.
- If `estimatedGrade` exists, show app grade card below.
- If not, show "앱 등급 분석 전" with `등급 확인` action.

#### 3. App Grading Result

Fields from `AssetDto`:

- `estimatedGrade`
- `centeringScore`
- `cornerScore`
- `surfaceScore`
- `whiteningScore`
- `centeringRatio`
- `detectionConfidence`
- `gradingAnalyzedAt`

Existing behavior:

- `_buildAssetGradeSection()` already shows `estimatedGrade` and four sub-scores.
- `_showGradingPhotos(assetId)` fetches `GET /api/assets/{assetId}/images` and displays `FRONT`/`BACK`.

New layout:

```text
앱 분석 결과
8.7 / 10
센터링 9.0  코너 8.5  표면 8.8  화이트닝 8.2
[분석 사진 보기] [다시 분석]
```

#### 4. Ownership Metadata

Fields:

- `purchasedAt`: from `AssetDto.purchasedAt`.
- `memo`: from `AssetDto.memo`.
- `createdAt`, `updatedAt`: available but lower priority.
- `isSelling`, `activeTradeId`: from `AssetDto.fromWithCardAndSelling`.

Display:

- Show `구매일` only if present.
- Show `메모` only if non-empty.
- Show selling state:
  - `판매중` and link to `/trades/{activeTradeId}` if `isSelling == true`.
  - otherwise show action row.

#### 5. Actions

Primary:

- `이 카드 판매하기` -> existing route `/trades/create` with current extra payload.

Secondary:

- `등급 확인` -> `/grading/capture`.
- `내 판매글 보러가기` -> `/trades/{activeTradeId}`.
- `자산 삭제` -> `DELETE /api/assets/{assetId}`. Keep in app bar or overflow, not primary body.

Route note:

- User requirement says "거래로 판매 버튼 -> `/trades/create`". Existing code already does this for normal sell flow.
- Existing helper `_showRawSellPriceSheet` and `/api/trades/from-asset` are used in `asset_screen.dart`; card detail currently routes to `/trades/create`. For consistency with requirement, keep `/trades/create`.

#### Non-owner Empty State

For non-owned cards, `내 자산` tab should not disappear. It should show:

```text
보유한 카드가 아닙니다
자산으로 추가하면 구매가, 손익, 등급 분석을 관리할 수 있습니다.
[스캔으로 추가] [직접 추가]
```

Supported endpoints:

- Direct add needs current user id from `GET /api/users/me`, then `POST /api/assets`.
- Current card detail does not load current user for non-owner add. Mark direct add from detail as **TBD** unless user id is available globally.

### `시세` Tab

Show these fields in order.

#### 1. KO Estimate Summary

Fields:

- `KO 추정가`: `_priceSummary['ko']['mid']`.
- `저가/고가 범위`: `_priceSummary['ko']['low']`, `_priceSummary['ko']['high']`.
- `basis`: `_priceSummary['ko']['basis']`.
- `confidence`: `_priceSummary['ko']['confidence']`.
- `domesticCount`: `_priceSummary['ko']['domesticCount']`.
- `마지막 업데이트`: `_priceSummary['ko']['asOfDate']`.

Display:

```text
KO 추정가
32,920원
28,000 ~ 37,900원
신뢰도 B · 국내 표본 3건 · 2026-05-11
```

If promo exclusive:

- Current code changes label based on `isPromoExclusive` and KO basis.
- Preserve behavior: promo cards may show `JP 시세` or `EN 시세` instead of `KO 예상 가치`.

#### 2. Trust Basis / Formula

Required by roadmap: "KO 추정가 근거 표시".

Data directly available now:

- `CardDto.enScrydexRef`, `CardDto.jpScrydexRef`.
- `CardPriceSummaryDto.charts.en.line.last.rawPrice`, `rawCurrency`.
- `CardPriceSummaryDto.charts.jp.line.last.rawPrice`, `rawCurrency`.
- `CardPriceSummaryDto.ko.basis`, `confidence`, `domesticCount`, `asOfDate`.

Not directly available in `price-summary`:

- Applied exchange rate.
- Applied coefficient value.
- Selected exact source formula fields.

Therefore:

- Show EN/JP raw basis from chart last point where available.
- Label exchange rate and coefficient as **TBD unless backend adds fields**.
- Do not invent exact 환율/계수 in UI.

Recommended backend enhancement:

```json
"ko": {
  "mid": 32920,
  "low": 28000,
  "high": 37900,
  "basis": "FORMULA",
  "confidence": "B",
  "domesticCount": 3,
  "asOfDate": "2026-05-11",
  "sourceMarket": "EN",
  "sourceRawPrice": 24.50,
  "sourceCurrency": "USD",
  "fxRate": 1350.0,
  "coefficient": 0.995
}
```

Until then:

```text
근거
EN RAW $24.50 · JP RAW ¥3,200
환율/계수 상세는 백엔드 응답 추가 필요
```

#### 3. Market Selector

Keep existing internal selector:

- `KO`
- `EN`
- `JP`

This is not the same as top-level tabs. It belongs inside `시세`.

Existing state:

- `_selectedMarket`: `KO` / `EN` / `JP`.
- `_selectedGlobalGrade`: `RAW` / `PSA10` / `PSA9`.
- `_selectedGrade` exists but KO grade selection is effectively unused.

Recommendation:

- Top-level tabs: `시세`, `내 자산`.
- Inside `시세`: segmented control `KO | EN | JP`.
- Inside EN/JP: grade chips `RAW NM`, `PSA 10`, `PSA 9`.
- KO tab: show RAW range only until graded KO estimate exists.

#### 4. Price Trend Chart

Use existing `_buildMarketChart(charts)` logic.

Fields:

- `charts.ko.chartType`, `reason`, `line`, `points`.
- `charts.en.line`, `psa10Line`, `psa9Line`.
- `charts.jp.line`, `psa10Line`, `psa9Line`.
- `ChartPoint.date`, `price`, `rawPrice`, `rawCurrency`.

Rules:

- Chart height `220`.
- If `chartType == NONE`: show current `_buildNoUsefulChartBox(reason)` copy.
- If line has fewer than 2 points: show "데이터 없음".
- Keep existing fallback from RAW to PSA10/PSA9 when selected grade lacks enough points.

#### 5. EN / JP Reference Prices

Fields:

- EN RAW: last `charts.en.line.price` or `rawPrice`.
- JP RAW: last `charts.jp.line.price` or `rawPrice`.
- EN PSA: `enPsa.psa10Usd`, `enPsa.psa9Usd`.
- JP PSA: `jpPsa.psa10Usd`, `jpPsa.psa9Usd`.

Note:

- DTO comments say PSA prices are USD for both EN and JP.
- Existing UI currently formats EN/JP current chips with `$`.

#### 6. Sell Orders / Recent Listings

Use existing `_listings` from `GET /api/trades?cardId={cardId}&page=0&size=20`.

Fields from `TradePostDto`:

- `tradeId`
- `price`
- `cardStatus`
- `condition`
- `gradingCompany`
- `gradeValue`
- `certNumber`
- `status`
- `createdAt`
- `seller.nickname`

Order:

1. `매도 호가`: lowest 5 listings sorted by `price`.
2. `최근 판매글`: existing card list, max 5 initially.
3. `전체 보기` optional later.

User requirement mentions `/api/trades/cards/summary`.

- Verified endpoint exists in `TradeController`: `GET /api/trades/cards/summary?size=20`.
- But it is card-level grouped summaries across cards and currently does **not** accept `cardId`.
- For this detail screen, current verified endpoint is `GET /api/trades?cardId={cardId}`.
- If per-card trade summary is required, add **TBD** endpoint `GET /api/trades/cards/{cardId}/summary` or add `cardId` param to existing summary.

---

## Flutter Implementation Approach

### Recommended Pattern

Use explicit `TabController` with `NestedScrollView`.

Why:

- `SliverAppBar` gives the large image hero and pinned tab bar in one structure.
- `NestedScrollView` coordinates collapsible header with tab bodies better than a `SingleChildScrollView` wrapping tabs.
- Explicit `TabController` is needed because initial tab depends on ownership after `_localAsset` is initialized.
- `PageView` alone does not solve sticky header or sliver collapse.
- `DefaultTabController` is acceptable only if the initial index never changes; here owner vs non-owner default matters.

### Code Skeleton

```dart
class _CardDetailScreenState extends State<CardDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool get _isOwned => _localAsset != null;

  @override
  void initState() {
    super.initState();
    _localAsset = widget.myAsset != null
        ? Map<String, dynamic>.from(widget.myAsset!)
        : null;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _localAsset != null ? 1 : 0,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assetCard = _localAsset?['card'] is Map
        ? Map<String, dynamic>.from(_localAsset!['card'] as Map)
        : null;
    final data = _cardDetail ?? widget.cardData ?? assetCard;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            stretch: true,
            backgroundColor: AppColors.bg,
            foregroundColor: AppColors.textPrimary,
            expandedHeight: 360,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              if (_localAsset != null)
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: _showAssetActions,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _CardDetailHero(
                card: data,
                asset: _localAsset,
                priceSummary: _priceSummary,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                color: AppColors.bg,
                child: TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: '시세'),
                    Tab(text: '내 자산'),
                  ],
                  indicatorColor: AppColors.blue,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textMuted,
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _MarketTab(
              loading: _loading,
              priceSummary: _priceSummary,
              listings: _listings,
              selectedMarket: _selectedMarket,
              selectedGlobalGrade: _selectedGlobalGrade,
              onMarketChanged: _setMarket,
              onGlobalGradeChanged: (grade) {
                setState(() => _selectedGlobalGrade = grade);
              },
            ),
            _AssetTab(
              asset: _localAsset,
              currentPrice: ((_priceSummary?['ko'] as Map?)?['mid'] as num?)
                  ?.toInt(),
              onAddAsset: _showAddAssetOptionsFromDetail, // TBD user id
              onSell: _openCreateTrade,
              onGrade: _openGrading,
              onShowImages: _showGradingPhotos,
            ),
          ],
        ),
      ),
      bottomNavigationBar: _localAsset != null
          ? _buildSellBar(
              name,
              rarity,
              imageUrl,
              resolveCdnImageUrl(data),
            )
          : null,
    );
  }
}
```

### Widget Extraction

Recommended extraction for implementation:

- `_CardDetailHero`
- `_MarketTab`
- `_AssetTab`
- `_PositionSummaryCard`
- `_GradingInfoCard`
- `_AppGradingCard`
- `_TradeListingsSection`

Keep these in the same file for tomorrow's implementation unless the file becomes hard to maintain. The current file is already large, but moving classes to separate files can be a second pass.

### Data Loading

Keep the current first load:

```dart
Future.wait([
  ApiClient.get('${ApiConstants.cards}/${widget.cardId}'),
  ApiClient.get('${ApiConstants.prices}/${widget.cardId}/price-summary'),
  ApiClient.get('/api/trades', params: {
    'cardId': widget.cardId,
    'page': 0,
    'size': 20,
  }),
]);
```

Keep asset refresh:

```dart
final assetId = _localAsset?['assetId'] as String?;
if (assetId != null) {
  final assetRes = await ApiClient.get('/api/assets/$assetId');
  _localAsset = Map<String, dynamic>.from(assetRes['data'] as Map);
}
```

Optimization from `docs/COST.md`:

- Do not refetch on ordinary back navigation.
- Refetch only after grading/sell/delete mutation returns `true`.
- Preserve zero-latency rendering from `widget.cardData` or `widget.myAsset.card`.

---

## Key UX Decisions

### Default Tab

- Non-owner: `시세`.
- Owner: `내 자산`.
- Tab order remains `시세 | 내 자산` for everyone.

Reason:

- Browsing user wants price/chart/trend.
- Owner wants purchase vs current, P&L, grade.
- Seller wants both; stable two-tab structure makes switching cheap.

### Empty States

`시세` no data:

- If `_priceSummary.ko.mid == null` and no EN/JP line: "아직 시세 데이터가 부족합니다".
- Show refs state:
  - `enScrydexRef`/`jpScrydexRef` missing: "scrydex 매핑 필요".
  - refs present but no chart: "최근 거래 데이터 부족".

`내 자산` non-owner:

- "보유한 카드가 아닙니다".
- CTA:
  - `스캔으로 추가` -> `/scanner`.
  - `직접 추가` -> **TBD** from detail because current add flow needs user id and exists in `asset_screen.dart`, not card detail.

`내 자산` owner missing purchase price:

- Show current market value.
- P&L row: "구매가를 입력하면 손익을 볼 수 있습니다".
- CTA `구매가 수정` requires existing `PUT /api/assets/{assetId}`. Endpoint exists, UI is **TBD**.

### Graded Card Display

Owned graded card:

- Hero top-left badge: `PSA 10`, `BGS 9.5`, `CGC 10`.
- `내 자산` tab first grade card uses gold border.
- Cert number is visible but secondary.
- Slab image from asset images should be displayed if `SLAB` exists.

Market tab:

- EN/JP grade chips remain `RAW NM`, `PSA 10`, `PSA 9`.
- KO graded market value is not currently in `CardPriceSummaryDto`. Label as `KO RAW 추정가` when the owned card is graded to avoid implying PSA Korean value.

### Rarity Badge Colors

Use `AppColors.rarityColor` as source of truth:

- `SSR`: `#FF6B6B`
- `SAR`: `#FFD700`
- `BWR`: `#B2FFB2`
- `CSR`: `#00E5FF`
- `CHR`: `#4FC3F7`
- `UR`: `#CE93D8`
- `SR`: `#9575CD`
- `AR`: `#FF9800`
- default: `AppColors.textMuted`

Current `card_detail_screen.dart` has a local `_rarityColor` that differs slightly. Recommendation: use `AppColors.rarityColor` in the redesign to match `asset_screen.dart`.

### Card Image Treatment

Recommendation: full hero card image at top, but not full screen width. Pokemon card aspect ratio means full width makes the image too tall on small phones. Use centered image with width around `62%` of viewport and a full-width background/scrim.

Implementation:

- `CardImage(width: imageWidth, height: imageWidth * 1.4)`.
- Use `fit: BoxFit.contain`, not `cover`, for detail hero.
- Overlay rarity/grade badges on the image area.
- Keep product metadata below image inside hero.

---

## ASCII Layout Sketch

### Owner

```text
┌────────────────────────────────────┐
│ ←                         ⋯        │
│                                    │
│            ┌──────────┐            │
│ [PSA 10]   │          │  [SAR]     │
│            │  CARD    │            │
│            │  IMAGE   │            │
│            │          │            │
│            └──────────┘            │
│ 리자몽 ex                           │
│ SAR · 201/165 · 스칼렛&바이올렛       │
│ KO 추정가 329,200원                  │
├────────────────────────────────────┤
│        시세        내 자산           │
├────────────────────────────────────┤
│ 내 자산 탭                          │
│ ┌────────────────────────────────┐ │
│ │ 평가금액              329,200원 │ │
│ │ +129,200원 (+64.6%)            │ │
│ │ 보유 1장 · 구매가 200,000원     │ │
│ └────────────────────────────────┘ │
│ ┌────────────────────────────────┐ │
│ │ PSA 10 · cert# 12345678        │ │
│ │ [SLAB IMAGE]                   │ │
│ └────────────────────────────────┘ │
│ ┌────────────────────────────────┐ │
│ │ 앱 분석 8.7 / 10               │ │
│ │ 센터링 코너 표면 화이트닝        │ │
│ └────────────────────────────────┘ │
├────────────────────────────────────┤
│ [등급 확인]      [이 카드 판매하기]  │
└────────────────────────────────────┘
```

### Non-owner

```text
┌────────────────────────────────────┐
│ ←                                  │
│            ┌──────────┐  [SAR]     │
│            │  CARD    │            │
│            │  IMAGE   │            │
│            └──────────┘            │
│ 리자몽 ex                           │
│ SAR · 201/165                       │
├────────────────────────────────────┤
│        시세        내 자산           │
├────────────────────────────────────┤
│ 시세 탭                             │
│ KO 추정가                            │
│ 329,200원                           │
│ 279,800 ~ 378,600원                 │
│ 신뢰도 B · 국내 표본 3건 · 05/11     │
│                                    │
│ [KO] [EN] [JP]                      │
│ ┌────────────────────────────────┐ │
│ │           PRICE CHART           │ │
│ └────────────────────────────────┘ │
│ 매도 호가                           │
│ RAW 320,000원                       │
│ PSA 10 1,200,000원                  │
│ 최근 판매글                          │
└────────────────────────────────────┘
```

---

## API Endpoints Required

Every endpoint below is verified against controllers unless marked TBD.

### Existing / Verified

- `GET /api/cards/{cardId}`
  - Verified in `CardController.getCard`.
  - Used for `CardDto`: name, image, rarity, collection number, product, scrydex refs, promo flag.

- `GET /api/prices/cards/{cardId}/price-summary`
  - Verified in `PriceController.getPriceSummary`.
  - Used for KO mid/low/high, confidence, asOfDate, charts, EN/JP PSA prices.

- `GET /api/trades?cardId={cardId}&page=0&size=20`
  - Verified in `TradeController.getTrades`.
  - Used for sell order and recent listing rows.

- `GET /api/assets/{assetId}`
  - Verified in `AssetController.getAsset`.
  - Used to refresh owner asset after entering detail from asset screen.

- `GET /api/assets/{assetId}/images`
  - Verified in `AssetController.getAssetImages`.
  - Used for `FRONT`, `BACK`, `SLAB` images.

- `DELETE /api/assets/{assetId}`
  - Verified in `AssetController.deleteAsset`.
  - Used by existing delete action.

- `PATCH /api/assets/{assetId}/grading-info`
  - Verified in `AssetController.updateGradingInfo`.
  - Used by graded sell/update flow.

- `POST /api/assets/{assetId}/slab-image`
  - Verified in `AssetController.uploadSlabImage`.
  - Used for slab upload.

- `POST /api/assets/{assetId}/grading`
  - Verified in `AssetController.saveGradingResult`.
  - Used by grading capture result save.

- `POST /api/trades`
  - Verified in `TradeController.createTrade`.
  - Used by `/trades/create` route when creating listing.

- `POST /api/trades/from-asset`
  - Verified in `TradeController.createTradeFromAsset`.
  - Used by existing asset screen quick sell flows.

- `GET /api/trades/{tradeId}`
  - Verified in `TradeController.getTrade`.
  - Used when opening active listing or listing rows.

- `DELETE /api/trades/{tradeId}`
  - Verified in `TradeController.deleteTrade`.
  - Used by existing stop selling flow.

- `GET /api/users/me`
  - Verified in `UserController`.
  - Needed only if card detail supports adding a non-owned card directly.

- `POST /api/assets`
  - Verified in `AssetController.registerAsset`.
  - Needed only if card detail supports adding a non-owned card directly.

- `PUT /api/assets/{assetId}`
  - Verified in `AssetController.updateAsset`.
  - Needed for future purchase price/quantity edit.

- `GET /api/trades/cards/summary?size=20`
  - Verified in `TradeController.getCardTradeSummaries`.
  - Current shape is cross-card summary, not detail-specific.

### Inferred / TBD

- `GET /api/trades/cards/{cardId}/summary`
  - Needed only if the `시세` tab must show per-card seller count / average / lowest without loading all listings.
  - Existing `/api/trades/cards/summary` has no `cardId` request param.

- Add `fxRate`, `coefficient`, `sourceMarket`, `sourceRawPrice`, `sourceCurrency` to `GET /api/prices/cards/{cardId}/price-summary`.
  - Needed for exact "환율 + 계수 표시".
  - Current DTO does not expose these fields.

- `GET /api/assets?userId={userId}&cardId={cardId}`
  - Useful if a user opens card detail from market/search without `myAsset` but owns the card.
  - Current asset list endpoint only requires `userId`; frontend can filter client-side but that is wasteful.

---

## Data Field Traceability

### Card Fields

- `cardId`: `CardDto.cardId`, `AssetDto.cardId`, `TradePostDto.cardId`.
- `name`: `CardDto.name`, `AssetDto.CardInfo.name`.
- `rarityCode`: `CardDto.rarityCode`, `AssetDto.CardInfo.rarityCode`.
- `collectionNumber`: `CardDto.collectionNumber`.
- `productName`, `seriesName`, `productType`: `CardDto` from `GET /api/cards/{cardId}`.
- `imageUrl`: `CardDto.imageUrl`, `AssetDto.CardInfo.imageUrl`, resolved by `resolveCardImageUrl`.
- `enScrydexRef`, `jpScrydexRef`: `CardDto`, `AssetDto.CardInfo`.
- `isPromoExclusive`, `promoType`: `CardDto`.

### Asset Fields

- `assetId`, `userId`, `cardId`: `AssetDto`.
- `quantity`: `AssetDto.quantity`.
- `purchasePrice`: `AssetDto.purchasePrice`.
- `language`: `AssetDto.language`.
- `cardStatus`: `AssetDto.cardStatus`.
- `gradingCompany`, `gradeValue`, `certNumber`: `AssetDto`.
- `estimatedGrade`, `centeringScore`, `cornerScore`, `surfaceScore`, `whiteningScore`, `centeringRatio`, `detectionConfidence`, `gradingAnalyzedAt`: `AssetDto`.
- `memo`, `purchasedAt`, `createdAt`, `updatedAt`: `AssetDto`.
- `isSelling`, `activeTradeId`: `AssetDto.fromWithCardAndSelling`.

### Price Fields

- `ko.mid`, `ko.low`, `ko.high`: `CardPriceSummaryDto.KoPrice`.
- `ko.basis`, `ko.confidence`, `ko.domesticCount`, `ko.asOfDate`: `CardPriceSummaryDto.KoPrice`.
- `charts.ko/en/jp.chartType`, `reason`, `line`, `points`, `psa10Line`, `psa9Line`: `CardPriceSummaryDto.ChartData`.
- `date`, `price`, `rawPrice`, `rawCurrency`: `CardPriceSummaryDto.ChartPoint`.
- `enPsa.psa10Usd`, `enPsa.psa9Usd`, `jpPsa.psa10Usd`, `jpPsa.psa9Usd`: `CardPriceSummaryDto.PsaPrices`.

### Trade Fields

- `tradeId`, `assetId`, `price`, `imageUrl`, `imageUrls`: `TradePostDto`.
- `cardStatus`, `condition`, `gradingCompany`, `gradeValue`, `certNumber`: `TradePostDto`.
- `status`, `viewCount`, `createdAt`: `TradePostDto`.
- `seller.nickname`, `seller.profileImageUrl`: `TradePostDto.SellerDto`.

---

## Edge Cases and Concerns

### No Price Data

- `ko.mid == null`: show `시세 데이터 없음`.
- EN/JP charts empty: show `scrydex 데이터 부족`.
- Existing `_buildNoUsefulChartBox` already distinguishes `FLAT_DATA` vs insufficient data.
- Do not show P&L if current market price is missing.

### Unowned Card

- Default tab `시세`.
- `내 자산` tab shows add CTA.
- No bottom sell bar.
- Deleting action hidden.

### Owned Card But Opened Without `myAsset`

Current card detail only knows ownership if `widget.myAsset` is passed. If user opens the same card from market/search, ownership may not be detected.

Options:

- Tomorrow: accept this limitation and show non-owner state from market entry.
- Later: after `GET /api/users/me`, call `GET /api/assets?userId=...` and filter by `cardId`, or add `GET /api/assets?userId=...&cardId=...`.

### Graded Card

- Current price summary KO is RAW-oriented. For graded owned cards, label current market value as `KO RAW 추정가 기준` unless graded KO endpoint exists.
- EN/JP PSA 10/9 can be displayed, but they are USD and not a Korean graded market estimate.
- `BRG` vs `BGS`: asset add flow uses `BGS`; one sell sheet uses `BRG`. Treat `BRG` as data typo to clean before release.

### Multiple Copies Owned

- `quantity` exists.
- Existing purchase price semantics are ambiguous for `quantity > 1`.
- Current asset portfolio logic compares one purchase price to one market price, then separately uses quantity for market value. This implies purchasePrice is per-card, but total purchase basis may be undercounted for multiple copies.
- For tomorrow: display `구매가 / 장` and compute total purchase as `purchasePrice * quantity`.
- Later: support lots if users buy multiple copies at different prices.

### Asset Images

- `GET /api/assets/{assetId}/images` returns image type and URL maps from `AssetImage`.
- Current UI only looks for `FRONT` and `BACK`; redesign should also look for `SLAB`.
- URL handling should follow existing `_photoTile`: absolute URL or `${ApiConstants.baseUrl}$url`.

### Loading and Errors

- Current code swallows errors with `catch (_) {}` and may show empty UI.
- For redesign, keep stale/fallback data visible and show small inline error rows:
  - `시세를 불러오지 못했습니다`
  - `판매글을 불러오지 못했습니다`
  - `자산 정보를 갱신하지 못했습니다`

### Performance

- `price-summary` already bundles KO/EN/JP charts, so do not split into multiple price calls.
- Do not call `/api/assets/{assetId}/images` during initial load unless `내 자산` tab is opened or the asset is graded/app-graded. Lazy load images.
- Preserve `docs/COST.md` mutation-aware refresh.

### Visual Risk

- Full-width card image can become too tall. Use full-width hero area, but card itself centered at constrained width.
- Text over card image needs bottom scrim for readability.
- Avoid nested cards. Tab content can have individual information cards, but do not put the whole tab body inside a giant card.

---

## Tomorrow Implementation Checklist

1. Replace `SingleChildScrollView` body with `NestedScrollView`.
2. Add `TabController(length: 2, initialIndex: owner ? 1 : 0)`.
3. Move current `_buildPriceSection`, `_buildOrderBookSection`, `_buildListingsSection` into `시세` tab.
4. Build new `내 자산` tab with position summary first, then current `_buildAssetGradeSection` content.
5. Keep existing owner `bottomNavigationBar` sell/grade actions.
6. Update hero image treatment with large aspect-ratio card and rarity/grade overlays.
7. Use `AppColors.rarityColor` instead of local rarity color mapping.
8. Add clear empty states for non-owner, no price, no purchase price.
9. Mark 환율/계수 exact display as backend DTO follow-up, unless implementing backend fields tomorrow.

