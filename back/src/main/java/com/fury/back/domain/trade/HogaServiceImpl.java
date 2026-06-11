package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaBoardResponse.HogaStatusValue;
import com.fury.back.domain.trade.dto.HogaLevelDto;
import com.fury.back.domain.trade.dto.HogaLevelResponse;
import com.fury.back.domain.trade.dto.HogaListingResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.chat.ChatRoomRepository;
import com.fury.back.domain.interest.PostInterestRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.storage.StorageKeyUrls;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class HogaServiceImpl implements HogaService {

    private final TradePostRepository tradePostRepository;
    private final BuyOrderRepository buyOrderRepository;
    private final UserRepository userRepository;
    // ASK listing engagement (chatCount / favoriteCount) batch count용.
    private final ChatRoomRepository chatRoomRepository;
    private final PostInterestRepository postInterestRepository;
    // 차단 사용자 호가 제외용.
    private final BlockRepository blockRepository;

    @Override
    public HogaBoardResponse getBoard(String cardId, HogaStatus status, String grade, String language, int limit, String viewerUserId) {
        String cardStatus = status.dbCardStatus();
        String gradingCompany = status.dbGradingCompany();
        String gradeValue = status.requiresGrade() ? grade : null;

        List<HogaLevelDto> rawAsks =
                tradePostRepository.findHogaLevels(cardId, cardStatus, language, gradingCompany, gradeValue);
        List<HogaLevelDto> rawBids =
                buyOrderRepository.findHogaLevels(cardId, cardStatus, language, gradingCompany, gradeValue);

        long askCount = rawAsks.stream().mapToLong(HogaLevelDto::countLong).sum();
        long bidCount = rawBids.stream().mapToLong(HogaLevelDto::countLong).sum();

        // 매도는 가격 내림차순으로 정렬되어 옴 → lowestAsk = 마지막 행.
        // 매수도 가격 내림차순 → highestBid = 첫 행.
        Long lowestAsk = rawAsks.isEmpty() ? null : rawAsks.get(rawAsks.size() - 1).priceLong();
        Long highestBid = rawBids.isEmpty() ? null : rawBids.get(0).priceLong();

        Long marketPrice = null;
        if (lowestAsk != null && highestBid != null) {
            marketPrice = (lowestAsk + highestBid) / 2;
        } else if (lowestAsk != null) {
            marketPrice = lowestAsk;
        } else if (highestBid != null) {
            marketPrice = highestBid;
        }
        long tickUnit = HogaTickResolver.resolve(marketPrice == null ? 1L : marketPrice);

        // Phase 4: viewerUserId 가 있으면 내 OPEN 가격 set 가져와 row 매칭. anonymous 시 빈 set.
        java.util.Set<Long> myAskPrices = (viewerUserId == null || viewerUserId.isBlank())
                ? java.util.Set.of()
                : tradePostRepository
                        .findMyOpenAskPrices(viewerUserId, cardId, cardStatus, language, gradingCompany, gradeValue)
                        .stream().map(Integer::longValue).collect(Collectors.toSet());
        java.util.Set<Long> myBidPrices = (viewerUserId == null || viewerUserId.isBlank())
                ? java.util.Set.of()
                : buyOrderRepository
                        .findMyOpenBidPrices(viewerUserId, cardId, cardStatus, language, gradingCompany, gradeValue)
                        .stream().map(Integer::longValue).collect(Collectors.toSet());

        List<HogaLevelResponse> asks = toLevels(rawAsks, limit, myAskPrices);
        List<HogaLevelResponse> bids = toLevels(rawBids, limit, myBidPrices);

        return new HogaBoardResponse(
                cardId,
                toStatusValue(status),
                tickUnit,
                marketPrice,
                lowestAsk,
                highestBid,
                askCount,
                bidCount,
                asks,
                bids);
    }

    @Override
    public HogaListingsResponse getListingsAtPrice(
            String cardId, HogaStatus status, String grade, String language, HogaSide side, long price, String viewerUserId) {
        String cardStatus = status.dbCardStatus();
        String gradingCompany = status.dbGradingCompany();
        String gradeValue = status.requiresGrade() ? grade : null;
        Integer priceI = Math.toIntExact(price);
        Set<String> blocked = blockedIds(viewerUserId);

        List<HogaListingResponse> listings = (side == HogaSide.ASK)
                ? buildAskListings(tradePostRepository.findHogaListings(
                        cardId, cardStatus, language, gradingCompany, gradeValue, priceI), blocked)
                : buildBidListings(buyOrderRepository.findHogaListings(
                        cardId, cardStatus, language, gradingCompany, gradeValue, priceI), blocked);

        return new HogaListingsResponse(
                cardId, status.name(), side.name(), price, listings.size(), listings);
    }

    @Override
    public HogaListingsResponse getTopListings(
            String cardId, HogaStatus status, String grade, String language, HogaSide side, int limit, String viewerUserId) {
        String cardStatus = status.dbCardStatus();
        String gradingCompany = status.dbGradingCompany();
        String gradeValue = status.requiresGrade() ? grade : null;
        org.springframework.data.domain.Pageable page =
                org.springframework.data.domain.PageRequest.of(0, limit);
        Set<String> blocked = blockedIds(viewerUserId);

        List<HogaListingResponse> listings = (side == HogaSide.ASK)
                ? buildAskListings(tradePostRepository.findTopHogaAskListings(
                        cardId, cardStatus, language, gradingCompany, gradeValue, page), blocked)
                : buildBidListings(buyOrderRepository.findTopHogaBidListings(
                        cardId, cardStatus, language, gradingCompany, gradeValue, page), blocked);

        // price=0: 전 가격 flat — 각 listing 의 자체 price 사용.
        return new HogaListingsResponse(
                cardId, status.name(), side.name(), 0L, listings.size(), listings);
    }

    /** viewer 가 차단한 사용자 id 집합 (one-directional, TradeServiceImpl 과 동일 정책). */
    private Set<String> blockedIds(String viewerUserId) {
        if (viewerUserId == null || viewerUserId.isBlank()) return Set.of();
        return blockRepository.findAllByBlockerId(viewerUserId).stream()
                .map(Block::getBlockedId)
                .collect(Collectors.toSet());
    }

    /** 매도 TradePost rows → 응답 listing (닉네임 + chat/favorite batch count). 차단 사용자 제외. */
    private List<HogaListingResponse> buildAskListings(List<TradePost> rowsIn, Set<String> blocked) {
        List<TradePost> rows = blocked.isEmpty() ? rowsIn
                : rowsIn.stream().filter(t -> !blocked.contains(t.getSellerId())).toList();
        if (rows.isEmpty()) return List.of();
        Map<String, User> users = usersById(rows.stream().map(TradePost::getSellerId).collect(Collectors.toSet()));
        // ASK batch count — chat_rooms / post_interests N+1 방지.
        List<String> tradeIds = rows.stream().map(TradePost::getTradeId).distinct().toList();
        Map<String, Long> chatCountMap = tradeIds.isEmpty()
                ? Map.of()
                : chatRoomRepository.countBySaleListingIdIn(tradeIds).stream()
                        .collect(Collectors.toMap(r -> (String) r[0], r -> (Long) r[1]));
        Map<String, Long> favoriteCountMap = tradeIds.isEmpty()
                ? Map.of()
                : postInterestRepository.countByTradeIdIn(tradeIds).stream()
                        .collect(Collectors.toMap(r -> (String) r[0], r -> (Long) r[1]));
        return rows.stream()
                .map(t -> {
                    User u = users.get(t.getSellerId());
                    return new HogaListingResponse(
                        t.getSellerId(),
                        u == null ? null : u.getNickname(),
                        u == null ? null : u.getProfileImageUrl(),
                        t.getPrice() == null ? 0L : t.getPrice().longValue(),
                        t.getDescription(),
                        t.getCreatedAt(),
                        t.getAssetId(),
                        t.getTradeId(),
                        null,
                        // Phase 1-7: storage key → /api/images/secure/{key} proxy URL 변환 (첫 사진만).
                        StorageKeyUrls.firstProxyUrl(t.getImageUrl()),
                        t.getStatus(),
                        chatCountMap.getOrDefault(t.getTradeId(), 0L),
                        favoriteCountMap.getOrDefault(t.getTradeId(), 0L));
                })
                .toList();
    }

    /** 매수 BuyOrder rows → 응답 listing. 차단 사용자 제외. */
    private List<HogaListingResponse> buildBidListings(List<BuyOrder> rowsIn, Set<String> blocked) {
        List<BuyOrder> rows = blocked.isEmpty() ? rowsIn
                : rowsIn.stream().filter(b -> !blocked.contains(b.getBuyerId())).toList();
        if (rows.isEmpty()) return List.of();
        Map<String, User> users = usersById(rows.stream().map(BuyOrder::getBuyerId).collect(Collectors.toSet()));
        return rows.stream()
                .map(b -> {
                    User u = users.get(b.getBuyerId());
                    return new HogaListingResponse(
                        b.getBuyerId(),
                        u == null ? null : u.getNickname(),
                        u == null ? null : u.getProfileImageUrl(),
                        b.getBidPrice().longValue(),
                        b.getMemo(),
                        b.getCreatedAt(),
                        null,
                        null,
                        b.getBuyOrderId(),
                        null,
                        null,
                        null,
                        null);
                })
                .toList();
    }

    /** group-by 결과를 응답 row + bar ratio로 변환. */
    private List<HogaLevelResponse> toLevels(List<HogaLevelDto> raw, int limit, Set<Long> myPrices) {
        if (raw.isEmpty()) return List.of();
        long max = raw.stream().mapToLong(HogaLevelDto::countLong).max().orElse(1L);
        List<HogaLevelResponse> out = new ArrayList<>(Math.min(raw.size(), limit));
        for (int i = 0; i < raw.size() && i < limit; i++) {
            HogaLevelDto d = raw.get(i);
            double ratio = max == 0 ? 0.0 : ((double) d.countLong()) / max;
            boolean hasMine = myPrices.contains(d.priceLong());
            out.add(new HogaLevelResponse(d.priceLong(), d.countLong(), ratio, hasMine));
        }
        return out;
    }

    /** 등록자 batch 조회 (닉네임 + 프로필 이미지). 호가 listing 아바타용. */
    private Map<String, User> usersById(Set<String> userIds) {
        if (userIds == null || userIds.isEmpty()) return Map.of();
        Set<String> ids = new HashSet<>(userIds);
        return userRepository.findAllById(ids).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u, (a, b) -> a));
    }

    private HogaStatusValue toStatusValue(HogaStatus status) {
        return switch (status) {
            case RAW -> HogaStatusValue.RAW;
            case PSA -> HogaStatusValue.PSA;
            case BRG -> HogaStatusValue.BRG;
        };
    }
}
