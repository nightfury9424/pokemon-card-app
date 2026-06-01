package com.fury.back.domain.trade.dto;

/**
 * Repository group-by projection. price + count(*).
 *
 * <p>JPQL SELECT NEW에서 사용. BuyOrder.bidPrice / TradePost.price 는 Integer이므로
 * record 필드도 Integer/Long으로 맞춤 (Hibernate boxing 일관성).
 *
 * <p>Service 단에서 long 변환해 HogaLevelResponse로 매핑.
 */
public record HogaLevelDto(Integer price, Long count) {

    public long priceLong() {
        return price == null ? 0L : price.longValue();
    }

    public long countLong() {
        return count == null ? 0L : count.longValue();
    }
}
