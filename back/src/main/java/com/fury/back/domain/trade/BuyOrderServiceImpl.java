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

    @Override
    public ReturnData<List<BuyOrderDto>> getByCard(String cardId) {
        if (cardId == null || cardId.isBlank()) {
            return ReturnData.badRequest("cardId는 필수입니다.");
        }
        List<BuyOrder> orders = buyOrderRepository.findOpenByCardIdOrderByBidPriceDesc(cardId);
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

        String cardId = params.getString("cardId");
        Integer bidPrice = params.getInteger("bidPrice");
        String cardStatus = params.getString("cardStatus");
        Integer qty = params.getInteger("qty");
        String gradingCompany = params.getString("gradingCompany");
        String gradeValue = params.getString("gradeValue");
        String memo = params.getString("memo");

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
        if (cardRepository.findById(cardId).isEmpty()) {
            return ReturnData.notFound("카드를 찾을 수 없습니다.");
        }

        // 5개 한도 체크
        long openCount = buyOrderRepository.countByBuyerIdAndStatus(buyerId, "OPEN");
        if (openCount >= MAX_OPEN_ORDERS_PER_USER) {
            return ReturnData.badRequest(
                    "매수 호가는 최대 " + MAX_OPEN_ORDERS_PER_USER + "개까지 등록 가능합니다.");
        }
        // 동일 카드 OPEN 1개 체크 (DB unique도 있지만 user-friendly 에러 위해 먼저)
        if (buyOrderRepository.findFirstByBuyerIdAndCardIdAndStatus(buyerId, cardId, "OPEN").isPresent()) {
            return ReturnData.badRequest("이미 같은 카드에 매수 호가가 등록되어 있습니다. 수정/취소 후 다시 시도해주세요.");
        }

        BuyOrder order = BuyOrder.builder()
                .buyOrderId(IdGenerator.generate())
                .buyerId(buyerId)
                .cardId(cardId)
                .bidPrice(bidPrice)
                .qty(qty != null && qty > 0 ? qty : 1)
                .cardStatus(cardStatus)
                .gradingCompany(gradingCompany)
                .gradeValue(gradeValue)
                .memo(memo)
                .status("OPEN")
                .build();
        BuyOrder saved = buyOrderRepository.save(order);

        // 같은 카드 보유한 사용자들에게 알림 (본인 제외)
        try {
            var holders = assetRepository.findByCardId(cardId).stream()
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
        return ReturnData.success(enrichWithDetails(List.of(order)).get(0));
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
