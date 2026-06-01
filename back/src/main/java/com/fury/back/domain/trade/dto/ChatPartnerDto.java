package com.fury.back.domain.trade.dto;

import java.time.LocalDateTime;

/**
 * 거래중 상대 선택 sheet 응답 — 판매글에 연결된 채팅방 후보 1건.
 *
 * <p>판매자가 "거래중" 상태로 변경할 때 chat room 리스트 중 선택. backend 가
 * 후보를 확정해서 frontend 가 권한/숨김 정책 누수 없이 표시.
 */
public record ChatPartnerDto(
        String chatRoomId,
        String buyerUserId,
        String buyerNickname,
        String buyerProfileImageUrl,
        String lastMessage,
        LocalDateTime lastMessageAt
) {}
