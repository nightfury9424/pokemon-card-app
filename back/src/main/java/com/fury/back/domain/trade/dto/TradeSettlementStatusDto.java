package com.fury.back.domain.trade.dto;

/**
 * 실거래가 입력 상태 — 완료 모달/인터셉터 노출 판단 + prefill 용.
 *
 * @param participant     내가 이 거래 당사자(판매자/매칭 buyer)인가
 * @param completed       거래가 완료(COMPLETED) 상태인가
 * @param reported        내가 이미 실거래가를 입력했는가
 * @param required        입력 요청해야 하는가 (participant && completed && !reported)
 * @param agreedPrice     원래 거래가(판매가) — 모달 prefill 기본값
 * @param myReportedPrice 이미 입력했다면 그 값 (없으면 null)
 * @param role            SELLER / BUYER / null
 */
public record TradeSettlementStatusDto(
        boolean participant,
        boolean completed,
        boolean reported,
        boolean required,
        Integer agreedPrice,
        Integer myReportedPrice,
        String role
) {}
