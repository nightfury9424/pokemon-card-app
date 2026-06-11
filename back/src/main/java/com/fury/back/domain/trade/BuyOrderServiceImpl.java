package com.fury.back.domain.trade;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.AssetRepository;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.notification.NotificationService;
import com.fury.back.domain.trade.dto.BuyOrderDto;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.storage.CardCdnUrls;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 매수 호가 서비스. 4차-Round4-4 Phase 1.
 *
 * 정책:
 * - OPEN 5개 한도 / 사용자 (app-level)
 * - 동일 카드 OPEN 1개만 (DB unique index 추가로 race condition 차단)
 * - GRADED 시 gradingCompany + gradeValue 필수
 * - 자동 매칭 X — markMatched는 외부 거래 완료 후 사용자가 수동 호출
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class BuyOrderServiceImpl implements BuyOrderService {

    private static final int MAX_OPEN_ORDERS_PER_USER = 5;

    private final BuyOrderRepository buyOrderRepository;
    private final CardRepository cardRepository;
    private final UserRepository userRepository;
    private final AssetRepository assetRepository;
    private final NotificationService notificationService;
    private final CardCdnUrls cardCdnUrls;
    // 2026-05-28 BUY chat — 상태 변경 시 해당 BuyOrder의 모든 chat_room에 SYSTEM fan-out.
    private final com.fury.back.domain.chat.ChatService chatService;
    // 2026-06-03 호가 교란 방지 — 매수 가격 밴드(상한) 검증용 KO 예상가 조회.
    private final com.fury.back.domain.price.PriceSnapshotRepository priceSnapshotRepository;

    // 휴대폰 인증 게이트 토글 — Flutter OTP 플로우 IPA 나가기 전엔 false(전원 차단 방지). prod에서 true로.
    @org.springframework.beans.factory.annotation.Value("${app.phone-gate.enabled:false}")
    private boolean phoneGateEnabled;

    @Override
    public ReturnData<List<BuyOrderDto>> getByCard(String cardId, String language) {
        if (cardId == null || cardId.isBlank()) {
            return ReturnData.badRequest("cardId는 필수입니다.");
        }
        List<BuyOrder> orders = buyOrderRepository.findOpenByCardIdOrderByBidPriceDesc(cardId);
        // 발매판 필터 (optional) — null/blank면 전체(하위호환), 지정 시 해당 발매판만.
        if (language != null && !language.isBlank()) {
            final String lang = language.trim().toUpperCase();
            orders = orders.stream().filter(o -> lang.equals(o.getLanguage())).toList();
        }
        return ReturnData.success(enrichWithDetails(orders));
    }

    @Override
    public ReturnData<Page<BuyOrderDto>> getByCardPaged(String cardId, int page, int size) {
        if (cardId == null || cardId.isBlank()) {
            return ReturnData.badRequest("cardId는 필수입니다.");
        }
        Page<BuyOrder> result = buyOrderRepository.findOpenPageByCardId(cardId, PageRequest.of(page, size));
        List<BuyOrderDto> enriched = enrichWithDetails(result.getContent());
        Page<BuyOrderDto> dtoPage = result.map(o -> enriched.stream()
                .filter(d -> d.getBuyOrderId().equals(o.getBuyOrderId()))
                .findFirst()
                .orElse(BuyOrderDto.from(o)));
        return ReturnData.success(dtoPage);
    }

    @Override
    public ReturnData<Page<BuyOrderDto>> getAllOpen(int page, int size) {
        Page<BuyOrder> result = buyOrderRepository.findByStatusOrderByBidPriceDescCreatedAtDesc(
                "OPEN", PageRequest.of(page, size));
        List<BuyOrderDto> enriched = enrichWithDetails(result.getContent());
        return ReturnData.success(result.map(o -> enriched.stream()
                .filter(d -> d.getBuyOrderId().equals(o.getBuyOrderId()))
                .findFirst()
                .orElse(BuyOrderDto.from(o))));
    }

    @Override
    public ReturnData<List<BuyOrderDto>> getMyOrders(String buyerId, String status, String cardId) {
        if (buyerId == null || buyerId.isBlank()) {
            return ReturnData.badRequest("buyerId는 필수입니다.");
        }
        String s = (status == null || status.isBlank()) ? "OPEN" : status;
        List<BuyOrder> orders;
        if (cardId != null && !cardId.isBlank()) {
            orders = buyOrderRepository.findByBuyerIdAndCardIdAndStatusOrderByCreatedAtDesc(buyerId, cardId, s);
        } else {
            orders = buyOrderRepository.findByBuyerIdAndStatusOrderByCreatedAtDesc(buyerId, s);
        }
        return ReturnData.success(enrichWithDetails(orders));
    }

    @Override
    @Transactional
    public ReturnData<BuyOrderDto> create(String buyerId, ParameterData params) {
        if (buyerId == null || buyerId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        // 휴대폰 인증 게이트 — 거래 행위 시점에만 요구. 클라가 코드 보고 인증 시트 띄움.
        if (phoneGateEnabled && !userRepository.findById(buyerId).map(User::isPhoneVerified).orElse(false)) {
            return ReturnData.fail("PHONE_VERIFICATION_REQUIRED", "휴대폰 인증 후 거래할 수 있어요.");
        }

        String cardId = params.getString("cardId");
        Integer bidPrice = params.getInteger("bidPrice");
        String cardStatus = params.getString("cardStatus");
        Integer qty = params.getInteger("qty");
        String gradingCompany = params.getString("gradingCompany");
        String gradeValue = params.getString("gradeValue");
        String memo = params.getString("memo");
        // 발매판(언어) — 매수자가 구하는 발매판 선택. 구버전 클라 하위호환 위해 미전달 시 KO default.
        String language = params.getString("language");
        if (language == null || language.isBlank()) language = "KO";
        language = language.trim().toUpperCase();
        if (!language.equals("KO") && !language.equals("JP") && !language.equals("EN")) {
            return ReturnData.badRequest("language는 KO/JP/EN 중 하나여야 합니다.");
        }

        if (cardId == null || cardId.isBlank() || bidPrice == null || bidPrice <= 0) {
            return ReturnData.badRequest("cardId, bidPrice(>0)는 필수입니다.");
        }
        if (cardStatus == null || (!cardStatus.equals("RAW") && !cardStatus.equals("GRADED"))) {
            return ReturnData.badRequest("cardStatus는 RAW 또는 GRADED여야 합니다.");
        }
        if ("GRADED".equals(cardStatus)) {
            if (gradingCompany == null || gradingCompany.isBlank() ||
                gradeValue == null || gradeValue.isBlank()) {
                return ReturnData.badRequest("GRADED는 gradingCompany, gradeValue가 필수입니다.");
            }
        } else {
            // RAW는 등급 정보 무시 (사용자 의도: RAW 자체 등급 무관)
            gradingCompany = null;
            gradeValue = null;
        }
        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) {
            return ReturnData.notFound("카드를 찾을 수 없습니다.");
        }
        // 존재 발매판 검증 — 그 카드가 실제 가진 발매판(KO/JP/EN)만 매수 가능 (없는 판 차단).
        if (!availableLanguages(card).contains(language)) {
            return ReturnData.badRequest("이 카드는 " + language + " 발매판이 없어요. 존재하는 발매판으로 매수해주세요.");
        }

        // 호가 교란 방지 — 시세 대비 과도한 고가 입찰 차단 (상한만, 저가 입찰은 무해하므로 허용)
        String priceErr = validateBidPrice(cardId, cardStatus, language, bidPrice);
        if (priceErr != null) return ReturnData.badRequest(priceErr);

        // 5개 한도 체크
        long openCount = buyOrderRepository.countByBuyerIdAndStatus(buyerId, "OPEN");
        if (openCount >= MAX_OPEN_ORDERS_PER_USER) {
            return ReturnData.badRequest(
                    "매수 호가는 최대 " + MAX_OPEN_ORDERS_PER_USER + "개까지 등록 가능합니다.");
        }
        // 동일 카드 OPEN 1개 체크 (DB unique도 있지만 user-friendly 에러 위해 먼저)
        if (buyOrderRepository.findFirstByBuyerIdAndCardIdAndLanguageAndStatus(buyerId, cardId, language, "OPEN").isPresent()) {
            return ReturnData.badRequest("이미 같은 카드(같은 발매판)에 매수 호가가 등록되어 있습니다. 수정/취소 후 다시 시도해주세요.");
        }

        BuyOrder order = BuyOrder.builder()
                .buyOrderId(IdGenerator.generate())
                .buyerId(buyerId)
                .cardId(cardId)
                .language(language)
                .bidPrice(bidPrice)
                .qty(qty != null && qty > 0 ? qty : 1)
                .cardStatus(cardStatus)
                .gradingCompany(gradingCompany)
                .gradeValue(gradeValue)
                .memo(memo)
                .status("OPEN")
                .build();
        BuyOrder saved = buyOrderRepository.save(order);

        // 같은 카드 + 같은 발매판 보유자에게만 알림 (본인 제외)
        try {
            final String langFinal = saved.getLanguage();
            var holders = assetRepository.findByCardId(cardId).stream()
                    .filter(a -> langFinal.equals(a.getLanguage())) // 같은 발매판 보유자만
                    .map(a -> a.getUserId())
                    .filter(uid -> uid != null && !uid.equals(buyerId))
                    .distinct()
                    .toList();
            if (!holders.isEmpty()) {
                String cardName = cardRepository.findById(cardId).map(Card::getName).orElse("카드");
                String buyerNickname = userRepository.findById(buyerId).map(User::getNickname).orElse("구매자");
                notificationService.notifyBuyOrderToCardHolders(holders, cardId, cardName, bidPrice, buyerNickname);
            }
        } catch (Exception ignore) {}

        return ReturnData.success(enrichWithDetails(List.of(saved)).get(0));
    }

    @Override
    @Transactional
    public ReturnData<BuyOrderDto> updateBidPrice(String buyOrderId, String buyerId, Integer newPrice) {
        if (newPrice == null || newPrice <= 0) {
            return ReturnData.badRequest("bidPrice(>0)는 필수입니다.");
        }
        BuyOrder order = buyOrderRepository.findById(buyOrderId).orElse(null);
        if (order == null) return ReturnData.notFound("매수 호가를 찾을 수 없습니다.");
        if (!order.getBuyerId().equals(buyerId)) return ReturnData.fail("F403", "권한이 없습니다.");
        if (!"OPEN".equals(order.getStatus())) {
            return ReturnData.badRequest("OPEN 상태에서만 수정 가능합니다.");
        }
        // 수정 시점의 현재 예상가로 재검증 (등록 후 시세 이동 + 의도적 과대 수정 차단)
        String priceErr = validateBidPrice(order.getCardId(), order.getCardStatus(), order.getLanguage(), newPrice);
        if (priceErr != null) return ReturnData.badRequest(priceErr);
        order.updateBidPrice(newPrice);
        return ReturnData.success(enrichWithDetails(List.of(order)).get(0));
    }

    @Override
    @Transactional
    public ReturnData<Void> cancel(String buyOrderId, String buyerId) {
        BuyOrder order = buyOrderRepository.findById(buyOrderId).orElse(null);
        if (order == null) return ReturnData.notFound("매수 호가를 찾을 수 없습니다.");
        if (!order.getBuyerId().equals(buyerId)) return ReturnData.fail("F403", "권한이 없습니다.");
        if (!"OPEN".equals(order.getStatus())) {
            return ReturnData.badRequest("OPEN 상태에서만 취소 가능합니다.");
        }
        order.updateStatus("CANCELED");
        // 2026-05-28: BUY chat fan-out — 채팅 중인 잠재 판매자에게 SYSTEM 알림.
        chatService.broadcastBuyOrderStatusChanged(buyOrderId, "CANCELED");
        return ReturnData.success();
    }

    @Override
    @Transactional
    public ReturnData<BuyOrderDto> markMatched(String buyOrderId, String buyerId, String tradeId) {
        BuyOrder order = buyOrderRepository.findById(buyOrderId).orElse(null);
        if (order == null) return ReturnData.notFound("매수 호가를 찾을 수 없습니다.");
        if (!order.getBuyerId().equals(buyerId)) return ReturnData.fail("F403", "권한이 없습니다.");
        if (!"OPEN".equals(order.getStatus())) {
            return ReturnData.badRequest("OPEN 상태에서만 체결 가능합니다.");
        }
        order.updateStatus("MATCHED");
        if (tradeId != null && !tradeId.isBlank()) order.updateMatchedTradeId(tradeId);
        // 2026-05-28: BUY chat fan-out — 채팅 중인 잠재 판매자들에게 매칭 알림.
        chatService.broadcastBuyOrderStatusChanged(buyOrderId, "MATCHED");
        return ReturnData.success(enrichWithDetails(List.of(order)).get(0));
    }

    /**
     * B2-12: 구매를 판매처럼 — 구매중(OPEN)→거래중(RESERVED, 상대 선택)→완료(COMPLETED).
     * 판매 TradeServiceImpl.updateStatus 대칭. RESERVED 시 chatRoomId(선택 상대) 기록.
     * B2-4 대칭: OPEN→COMPLETED 직접 금지(거래중 거쳐야 완료).
     */
    @Override
    @Transactional
    public ReturnData<BuyOrderDto> updateStatus(String buyOrderId, String buyerId, String status, String chatRoomId) {
        if (status == null || status.isBlank()) return ReturnData.badRequest("status는 필수입니다.");
        BuyOrder order = buyOrderRepository.findById(buyOrderId).orElse(null);
        if (order == null) return ReturnData.notFound("매수 호가를 찾을 수 없습니다.");
        if (!order.getBuyerId().equals(buyerId)) return ReturnData.fail("F403", "권한이 없습니다.");
        if (status.equals(order.getStatus())) {
            return ReturnData.success(enrichWithDetails(List.of(order)).get(0));
        }
        if ("COMPLETED".equals(status) && "OPEN".equals(order.getStatus())) {
            return ReturnData.fail("F409", "거래중으로 변경한 뒤 완료할 수 있어요.");
        }
        // Codex B2-12 review: RESERVED 는 거래 상대(채팅방) 필수. 없으면 판매자가 실거래가 입력 영구 불가
        // (buySettlementSellerOf 가 activeChatRoomId 로만 SELLER 해소). 프론트는 항상 전달 — 방어선.
        if ("RESERVED".equals(status) && (chatRoomId == null || chatRoomId.isBlank())) {
            return ReturnData.badRequest("거래 상대(채팅방)가 필요합니다.");
        }
        order.updateStatus(status);
        if ("RESERVED".equals(status) && chatRoomId != null && !chatRoomId.isBlank()) {
            order.setActiveChatRoom(chatRoomId);
        } else if ("OPEN".equals(status)) {
            order.clearActiveChatRoom();
        }
        buyOrderRepository.save(order);
        chatService.broadcastBuyOrderStatusChanged(buyOrderId, status);
        return ReturnData.success(enrichWithDetails(List.of(order)).get(0));
    }

    /**
     * 매수 호가 가격 가드 — 호가 교란 방지. <b>상한만</b> 검증한다.
     * <p>BID의 교란 벡터는 고가 입찰뿐(최상단 BID로 떠 수요·시세를 부풀림). 저가 입찰은
     * 호가창 맨 아래 깔려 무해하고 자기손해이며, 카드 하자 등 정당한 저가 의사일 수 있어 허용.
     * 판매(매도) {@code validateListingPrice} 와 대칭이되 하한은 적용하지 않는다.
     * <p>GRADED는 KO 예상가가 RAW 기준이라 부정확 → skip. est 없으면 절대 상한(1천만)만.
     * 밴드는 판매와 동일한 {@code TradeServiceImpl.priceBand} 재사용.
     *
     * @return 위반 메시지(있으면), 통과 시 null
     */
    private String validateBidPrice(String cardId, String cardStatus, String language, int bidPrice) {
        if ("GRADED".equals(cardStatus)) return null;
        if (bidPrice > TradeServiceImpl.ABSOLUTE_MAX_PRICE) {
            return "비정상적으로 높은 구매 희망가는 등록할 수 없습니다.";
        }
        // 발매판별 기준가: KO=KO_ESTIMATED(타이트), JP/EN=SCRYDEX 참고가 느슨 상한 — 상한만 검사(하한 없음).
        long[] range = TradeServiceImpl.resolveAllowedPriceRange(priceSnapshotRepository, cardId, language);
        if (bidPrice > range[1]) {
            return "시세 대비 지나치게 높은 구매 희망가는 등록할 수 없습니다.";
        }
        return null;
    }

    /** 카드가 실제 가진 발매판(KO/JP/EN) — language=KO 또는 jp/enScrydexRef 존재 기준 (스캐너 등록과 동일 원칙). */
    private java.util.Set<String> availableLanguages(Card card) {
        java.util.Set<String> langs = new java.util.LinkedHashSet<>();
        String lang = card.getLanguage();
        if ("KO".equalsIgnoreCase(lang)) langs.add("KO");
        if ("JP".equalsIgnoreCase(lang) || hasScrydexRef(card.getJpScrydexRef())) langs.add("JP");
        if ("EN".equalsIgnoreCase(lang) || hasScrydexRef(card.getEnScrydexRef())) langs.add("EN");
        if (langs.isEmpty()) langs.add("KO");
        return langs;
    }

    /** scrydex ref 유효성 — null/blank/"NO_..."(결측 sentinel)는 없는 것으로 (코드베이스 관습). */
    private static boolean hasScrydexRef(String ref) {
        return ref != null && !ref.isBlank() && !ref.startsWith("NO_");
    }

    private List<BuyOrderDto> enrichWithDetails(List<BuyOrder> orders) {
        if (orders.isEmpty()) return List.of();
        List<String> buyerIds = orders.stream().map(BuyOrder::getBuyerId).distinct().toList();
        List<String> cardIds = orders.stream().map(BuyOrder::getCardId).distinct().toList();
        Map<String, User> userMap = userRepository.findAllById(buyerIds).stream()
                .collect(Collectors.toMap(User::getUserId, Function.identity()));
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds).stream()
                .collect(Collectors.toMap(Card::getCardId, Function.identity()));
        return orders.stream()
                .map(o -> {
                    final Card card = cardMap.get(o.getCardId());
                    return BuyOrderDto.fromWithDetails(
                            o,
                            userMap.get(o.getBuyerId()),
                            card,
                            cardCdnUrls.forCard(card));
                })
                .toList();
    }
}
