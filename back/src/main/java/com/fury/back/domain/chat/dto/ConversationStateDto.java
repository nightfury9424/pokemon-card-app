package com.fury.back.domain.chat.dto;

/**
 * 채팅방 진입/active 시점 conversation 상태.
 *
 * <p>차단/거래중 비선택/상대 나감 관계에 따라 클라이언트가 입력창 비활성화 +
 * 안내 banner + 점점점 메뉴 label (차단/차단해제) 분기를 단일 진실원으로 결정.
 *
 * @param canSendMessage 메시지 전송 가능 여부. 한쪽이라도 차단 OR 상대 나감 OR
 *                       거래중 비선택 상태면 false.
 * @param blockNotice    배너 안내 문구. null 이면 표시 안 함.
 *                       우선순위: blockedByMe → blockedByOther → otherLeft →
 *                       isExcludedFromActiveTrade → null.
 * @param blockedByMe    내가 상대를 차단했는지. 메뉴 "차단 해제" label 트리거.
 * @param blockedByOther 상대가 나를 차단했는지. mutual block 시 한쪽 해제해도 banner 유지 판단용.
 * @param otherLeft      상대가 채팅방을 나갔는지. "상대방이 채팅방을 나갔습니다." 안내.
 * @param isExcludedFromActiveTrade 거래중("RESERVED") 상태인데 이 채팅방이
 *                       activeChatRoomId 가 아닌 경우. 다른 buyer 가 선택됨 →
 *                       "다른 사용자와 거래가 진행 중입니다." 안내 + 입력 비활성.
 */
public record ConversationStateDto(
        boolean canSendMessage,
        String blockNotice,
        boolean blockedByMe,
        boolean blockedByOther,
        boolean otherLeft,
        boolean isExcludedFromActiveTrade
) {}
