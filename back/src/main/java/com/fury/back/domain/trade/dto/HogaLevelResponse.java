package com.fury.back.domain.trade.dto;

/**
 * 호가창 한 행 응답.
 *
 * @param price    호가 가격 (KRW)
 * @param count    같은 가격에 등록된 호가 건수
 * @param barRatio 잔량 막대 비율 (0.0~1.0, ask/bid 각각의 최대 count 기준)
 * @param hasMine  현재 로그인 유저(viewer)가 이 가격에 OPEN 주문/판매글을 가지고 있는지 (Phase 4)
 */
public record HogaLevelResponse(long price, long count, double barRatio, boolean hasMine) {}
