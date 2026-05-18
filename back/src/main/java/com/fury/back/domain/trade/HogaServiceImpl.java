package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaBoardResponse.HogaStatusValue;
import com.fury.back.domain.trade.dto.HogaLevelDto;
import com.fury.back.domain.trade.dto.HogaLevelResponse;
import com.fury.back.domain.trade.dto.HogaListingResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
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

    @Override
    public HogaBoardResponse getBoard(String cardId, HogaStatus status, String grade, int limit) {
        String cardStatus = status.dbCardStatus();
        String gradingCompany = status.dbGradingCompany();
        String gradeValue = status.requiresGrade() ? grade : null;

        List<HogaLevelDto> rawAsks =
                tradePostRepository.findHogaLevels(cardId, cardStatus, gradingCompany, gradeValue);
        List<HogaLevelDto> rawBids =
                buyOrderRepository.findHogaLevels(cardId, cardStatus, gradingCompany, gradeValue);

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

        List<HogaLevelResponse> asks = toLevels(rawAsks, limit);
        List<HogaLevelResponse> bids = toLevels(rawBids, limit);

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
            String cardId, HogaStatus status, String grade, HogaSide side, long price) {
        String cardStatus = status.dbCardStatus();
        String gradingCompany = status.dbGradingCompany();
        String gradeValue = status.requiresGrade() ? grade : null;
        Integer priceI = Math.toIntExact(price);

        List<HogaListingResponse> listings;
        if (side == HogaSide.ASK) {
            List<TradePost> rows =
                    tradePostRepository.findHogaListings(
                            cardId, cardStatus, gradingCompany, gradeValue, priceI);
            Map<String, String> nicks = nicknames(rows.stream().map(TradePost::getSellerId).collect(Collectors.toSet()));
            listings = rows.stream()
                    .map(t -> new HogaListingResponse(
                            t.getSellerId(),
                            nicks.get(t.getSellerId()),
                            t.getPrice() == null ? 0L : t.getPrice().longValue(),
                            t.getDescription(),
                            t.getCreatedAt(),
                            t.getAssetId(),
                            t.getTradeId(),
                            null,
                            t.getImageUrl()))
                    .toList();
        } else {
            List<BuyOrder> rows =
                    buyOrderRepository.findHogaListings(
                            cardId, cardStatus, gradingCompany, gradeValue, priceI);
            Map<String, String> nicks = nicknames(rows.stream().map(BuyOrder::getBuyerId).collect(Collectors.toSet()));
            listings = rows.stream()
                    .map(b -> new HogaListingResponse(
                            b.getBuyerId(),
                            nicks.get(b.getBuyerId()),
                            b.getBidPrice().longValue(),
                            b.getMemo(),
                            b.getCreatedAt(),
                            null,
                            null,
                            b.getBuyOrderId(),
                            null))
                    .toList();
        }

        return new HogaListingsResponse(
                cardId, status.name(), side.name(), price, listings.size(), listings);
    }

    /** group-by 결과를 응답 row + bar ratio로 변환. */
    private List<HogaLevelResponse> toLevels(List<HogaLevelDto> raw, int limit) {
        if (raw.isEmpty()) return List.of();
        long max = raw.stream().mapToLong(HogaLevelDto::countLong).max().orElse(1L);
        List<HogaLevelResponse> out = new ArrayList<>(Math.min(raw.size(), limit));
        for (int i = 0; i < raw.size() && i < limit; i++) {
            HogaLevelDto d = raw.get(i);
            double ratio = max == 0 ? 0.0 : ((double) d.countLong()) / max;
            out.add(new HogaLevelResponse(d.priceLong(), d.countLong(), ratio));
        }
        return out;
    }

    private Map<String, String> nicknames(Set<String> userIds) {
        if (userIds == null || userIds.isEmpty()) return Map.of();
        Set<String> ids = new HashSet<>(userIds);
        return userRepository.findAllById(ids).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u.getNickname() == null ? "" : u.getNickname(), (a, b) -> a));
    }

    private HogaStatusValue toStatusValue(HogaStatus status) {
        return switch (status) {
            case RAW -> HogaStatusValue.RAW;
            case PSA -> HogaStatusValue.PSA;
            case BRG -> HogaStatusValue.BRG;
        };
    }
}
