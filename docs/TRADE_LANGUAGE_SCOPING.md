# 거래 발매판(언어) 분리 — 설계/구현 트래커

**목표**: KO/JP/EN 발매판별 가치가 다른데, 현재 매도(TradePost)·매수(BuyOrder)에 language 없어 cardId 단위로만 묶여 JP 카드가 KO 호가창에 섞임. → 매도·매수·호가창을 발매판별 완전 분리.
**원칙**: 천천히 **제대로** (빠르게 X). 데이터 정합성 우선.
**대상**: 1.0.1 (FE는 현재 제출본 202606111045 취소→재빌드 합류, BE는 prod 별도 배포). Codex 설계 `019eb4a0`.
**확정 결정**: ①매도 = `assetId` 필수(어느 판인지 asset.language로 확정) ②가격밴드 언어별(KO=KO_ESTIMATED/JP=SCRYDEX_JP/EN=SCRYDEX_EN, ref없으면 느슨한 상한).

## BE (먼저)
- [x] **엔티티** `TradePost.language` + `BuyOrder.language` (KO/JP/EN, varchar(10), NOT NULL) ✓
- [x] **마이그** `V20260611__add_trade_language_scope.sql` ✓ (컬럼+백필[asset→card→KO]+CHECK+인덱스+buy_orders unique `uq_buy_orders_buyer_card_lang_open` 재생성). ★기존 데이터 trade_posts 1/buy_orders 0 = 백필 trivial.
- [ ] DTO(TradePostDto/BuyOrderDto/Hoga응답) language 필드.
  - 인덱스: `trade_posts(card_id,language,status,card_status,grading_company,grade_value,price)`, `buy_orders(card_id,language,status,card_status,grading_company,grade_value,bid_price)`, partial unique `buy_orders(buyer_id,card_id,language) WHERE status='OPEN'`.
  - BuyOrder 기존 중복체크 `(buyer,card,OPEN)` → `(buyer,card,language,OPEN)`. 기존 unique drop/recreate.
- [ ] 매도: `createTradeFromAsset`/`createTrade` → `TradePost.language = asset.language`. assetId 필수 강제. 매수자 알림 = 같은 `cardId+language` BuyOrder만.
- [ ] 매수: `POST /api/buy-orders` body `language`. 중복체크 +language. 보유자 알림 = `asset.cardId+asset.language` 일치자만. 수정 시 order.language 기준 재검증.
- [ ] Hoga: `HogaController` `@RequestParam(defaultValue="KO") language` + `parseLanguage()`(KO/JP/EN외 400). `HogaService(Impl)` 전 메서드(findHogaLevels/findHogaListings/findTopHogaAsk/Bid/findMyOpenAsk/Bid) `language` 필터. askCount/bidCount/lowestAsk/highestBid/hasMine 언어별.
- [ ] 가격밴드: `validateListingPrice(cardId,language,cardStatus,price)`/`validateBidPrice(...)`. RAW: KO→KO_ESTIMATED, JP→SCRYDEX_JP, EN→SCRYDEX_EN. GRADED skip(후속). ref없으면 느슨 상한.

## FE (`front/lib/features/card/hoga/*`)
★**디자인 원칙(사용자 강조)**: 기존 앱 패턴 그대로 **이질감 0** — 차트의 KO/JP/EN 탭 컴포넌트 + `AppSegmentedToggle`(스캐너 등록시트) 재사용. 새 스타일/색/컴포넌트 만들지 말 것.
- [ ] 호가창 KO/JP/EN 탭(차트 패턴 재사용, 3개 다 노출 — "시세없음"과 "거래시장없음" 구분). card_detail `_selectedMarket` 연동 or 별도 탭.
- [ ] `hoga_board.dart` language prop + cache key(+language) + didUpdateWidget clear. `hoga_api.dart` fetchBoard/Listings/TopListings에 language query.
- [ ] `hoga_row_detail_sheet`/`pre_order_match_sheet` language 전달. 매도 매칭=asset.language, 매수=현재 호가 탭.

## 위험요소 (Codex)
기존 row 백필 모호(테스트DB wipe로 거의 0일 듯 — 확인). BuyOrder unique 변경. JP/EN 가격밴드 오차. 구버전 클라가 language 없이 등록 시 KO default.

## 배포
BE: prod (마이그 = backup+검증+롤백). FE: 1.0.1 제출취소→재빌드→재제출.

## 진행 상태
- ✅ **Chunk1** 마이그(V20260611, MULTI→KO normalize 추가)+엔티티 / ✅ **Chunk2** 매도2경로·매수 write-side language + DTO 매핑 — Codex 리뷰 `019eb4b6` + High fix(MULTI 방어 런타임2곳+마이그) + `compileJava` OK.
- ⏳ **Chunk3** read-side: Hoga 쿼리 language 필터 + Controller param + 가격밴드 언어별.
- ⏳ **Chunk2.5** 알림 scoping(매도→cardId+language 매수자만, 매수→cardId+language 보유자만). ⏳ **FE** 호가 탭.

## FE 상세 요구 (사용자 2026-06-11, 디자인 이질감 0 — 차트 탭/AppSegmentedToggle 재사용)
1. 호가 보드: RAW/PSA/BRG 탭 **위에** KO/JP/EN 탭 추가(차트 KO/JP/EN과 동일 컴포넌트). 선택 언어로 호가 필터.
2. 판매글/구매글 폼: 발매판 — 매도=내 자산 언어 표시, 매수=KO/JP/EN 선택.
3. ★예상가 자동입력: 판매/구매 가격칸 default = 그 발매판 예상가(KO=KO예상가/JP=SCRYDEX_JP/EN=SCRYDEX_EN). 현재 빈칸 → 자동 prefill. (신규 요구)

## ★존재 발매판만 (사용자 2026-06-11, BE+FE — 스캐너 fix 동일 원칙)
카드 실제 보유 발매판만 거래/호가 노출. 판단 = language=KO/koCardCode→KO, jpScrydexRef→JP, enScrydexRef→EN (CardDto, 스캐너 등록시트 resolveCardImageUrl 로직 재사용).
- 호가 보드 탭 = 존재 발매판만 (고흐피카츄 EN-only → EN 탭만).
- 매수 = 존재 발매판만 BuyOrder 허용 — BE `BuyOrderServiceImpl.create`에 검증 추가(없는 판 400) + FE 구매 선택도 존재 발매판만.
- 매도 = 내 자산 언어(이미 존재). 별도 검증 불필요.
- BE: `availableLanguages(card)` 헬퍼(language+jp/enScrydexRef) → 매수 검증 + Hoga 응답/카드 DTO로 FE에 노출(탭 결정용).
- ✅ **Chunk3 BE 완료** (compileJava OK): Hoga 쿼리 8개 language 필터(BuyOrder+TradePost repo) + HogaService/Impl/Controller language param+parseLanguage + BuyOrderServiceImpl availableLanguages 헬퍼+매수 존재검증 + 가격밴드 per-language(resolveAllowedPriceRange 3-arg: KO=KO_ESTIMATED타이트/JP·EN=SCRYDEX ×3느슨 + validateListing/Bid + 호출부 5곳[createTrade·FromAsset·BuyOrder create·update·updateTrade]). Codex 리뷰 대기.
- ⏳ **Chunk2.5** 알림 scoping. ⏳ **FE**(호가탭·매수매도 language·예상가자동입력·존재발매판). ⏳ 배포(BE prod 마이그+FE 1.0.1).

## Chunk3 리뷰 반영 (Codex 019eb4cd)
- ✅ High: `availableLanguages` NO_ ref 제외(`hasScrydexRef`: null/blank/"NO_" = 없음). NO_JP/NO_EN 카드 매수 차단 정상화.
- ✅ Medium: 매도 알림(같은 cardId+language 매수자만)·매수 알림(같은 cardId+language 보유자만) in-memory 필터. compileJava OK.
- ⚠️ 스코프 미결: 목록 API `/trades?cardId=`·`/buy-orders/cards/{cardId}`는 아직 언어혼합 → **FE 단계서 실사용처 보고** 필터 여부 결정(호가 board는 분리 완료). 
- ✅ **BE 코어 완료** (Chunk1+2+3+알림, Codex 2라운드 리뷰 + 컴파일). 다음 = FE → 배포.

## FE 진행 (2026-06-11)
- ✅ **BE 100%** (Chunk1+2+3 + 알림 + 목록API language 필터: getByCard in-memory / getTrades→findOpenByCardId·findFilteredExcludingSellers optional `:language` / 컨트롤러 language param). 전부 compileJava OK.
- ✅ **FE 기반**: hoga_api.dart 3메서드 `language` param / HogaBoard `language` prop+cache key(+language)+fetch 전달+didUpdate / card_detail HogaBoard에 `_selectedMarket` 전달(board 언어 wiring).
- ⏳ **FE 남은**: ①거래탭 KO/JP/EN 탭 노출(차트 `_buildMarketTabs` 재사용 or 카드-에디션 기반, raw/psa/brg 위) ②card_detail `/api/trades`·`/api/buy-orders/cards` 로드에 language ③hoga_row_detail_sheet/pre_order_match_sheet fetchListings/fetchTopListings에 language ④매도/매수 시트 발매판 표시·선택 + ★예상가 자동입력 ⑤존재발매판만(card refs).

## FE 진행 2 (2026-06-11)
- ✅ 거래탭 KO/JP/EN 탭(_buildMarketTabs 재사용, 발매판>1일때, raw/psa/brg 위) + HogaBoard language:_selectedMarket.
- ✅ 시트 language: HogaRowDetailSheet/PreOrderMatchSheet language param + fetchListings/fetchTopListings 전달, onRowTap/_onSellTap/_onBuyTap에서 _selectedMarket 전달.
- ✅ 매수 POST /api/buy-orders에 language:_selectedMarket. 매도=/trades/create에 assetId→BE가 asset.language 추론(FE 변경 불필요).
- ✅ ★홈 캐러셀 라벨 버그 fix(Codex 019eb4e3): _CarouselCard assetLanguage=asset.language??card.language → JP=일본판시세/EN=영문판시세/KO=PriceLabel. 가격 displayPrice는 BE가 이미 asset.language 기준.
- ✅ flutter analyze 클린(에러0).
- ⏳ 예상가 자동입력 prefill per-language(Codex 자문중) + Codex FE 사후리뷰.
