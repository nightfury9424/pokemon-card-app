package com.fury.back.domain.trade.dto;

/**
 * 호가창 한 행 응답.
 *
 * @param price    호가 가격 (KRW)
 * @param count    같은 가격에 등록된 호가 건수
 * @param barRatio 잔량 막대 비율 (0.0~1.0, ask/bid 각각의 최대 count 기준)
 */
public record HogaLevelResponse(long price, long count, double barRatio) {}
