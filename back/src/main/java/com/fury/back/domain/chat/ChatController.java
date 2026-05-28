package com.fury.back.domain.chat;

import com.fury.back.common.ApiResponse;
import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.chat.dto.ConversationStateDto;
import com.fury.back.domain.chat.dto.SendMessageRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.security.Principal;
import java.util.List;
import java.util.Map;

@RestController
@RequiredArgsConstructor
@RequestMapping("/api/chat")
public class ChatController {

    private final ChatService chatService;
    private final SimpMessagingTemplate messagingTemplate;

    // 채팅방 입장 (없으면 생성) — SALE chat (TradePost 기반)
    @PostMapping("/rooms")
    public ApiResponse<ChatRoomDto> enterRoom(
            @RequestBody Map<String, String> body,
            @AuthenticationPrincipal String userId) {
        String saleListingId = body.get("saleListingId");
        return ApiResponse.ok(chatService.getOrCreateRoom(saleListingId, userId));
    }

    // 2026-05-28: BUY chat 입장 (없으면 생성) — BuyOrder 기반. 잠재 판매자 → BuyOrder 작성자에게 채팅 시작.
    // 별도 endpoint 로 분리 — validation 명확화 + swagger 분리 (Codex E).
    @PostMapping("/rooms/from-buy-order")
    public ApiResponse<ChatRoomDto> enterRoomFromBuyOrder(
            @RequestBody Map<String, String> body,
            @AuthenticationPrincipal String userId) {
        String buyOrderId = body.get("buyOrderId");
        return ApiResponse.ok(chatService.getOrCreateRoomFromBuyOrder(buyOrderId, userId));
    }

    // 내 채팅방 목록
    @GetMapping("/rooms")
    public ApiResponse<List<ChatRoomDto>> getMyRooms(@AuthenticationPrincipal String userId) {
        return ApiResponse.ok(chatService.getMyRooms(userId));
    }

    // 메시지 히스토리
    @GetMapping("/rooms/{roomId}/messages")
    public ApiResponse<List<ChatMessageDto>> getMessages(
            @PathVariable String roomId,
            @AuthenticationPrincipal String userId) {
        return ApiResponse.ok(chatService.getMessages(roomId, userId));
    }

    // Bundle 1.5 (active read gap): chat_room active 상태에서 새 메시지 도착 시 즉시 read 처리.
    // 메시지 리스트 반환 X — lightweight. ChatReadEventListener가 AFTER_COMMIT broadcast.
    @PostMapping("/rooms/{roomId}/read")
    public ApiResponse<Void> markAsRead(
            @PathVariable String roomId,
            @AuthenticationPrincipal String userId) {
        chatService.markRoomAsRead(roomId, userId);
        return ApiResponse.ok();
    }

    // Phase 1: 채팅방 나가기 — 본인 hidden_at set. DB 보존, 본인 list 미노출.
    @PostMapping("/rooms/{roomId}/leave")
    public ApiResponse<Void> leaveRoom(
            @PathVariable String roomId,
            @AuthenticationPrincipal String userId) {
        chatService.leaveRoom(roomId, userId);
        return ApiResponse.ok();
    }

    // Phase 1: 채팅방 입력창/안내 상태 (canSendMessage + blockNotice). 진입 시 호출.
    @GetMapping("/rooms/{roomId}/conversation-state")
    public ApiResponse<ConversationStateDto> getConversationState(
            @PathVariable String roomId,
            @AuthenticationPrincipal String userId) {
        return ApiResponse.ok(chatService.getConversationState(roomId, userId));
    }

    // WebSocket - 메시지 전송
    @MessageMapping("/room/{roomId}")
    public void sendMessage(
            @DestinationVariable String roomId,
            @Payload SendMessageRequest request,
            Principal principal) {
        String senderUserId = principal != null ? principal.getName() : request.getSenderUserId();
        ChatMessageDto msg = chatService.sendMessage(roomId, senderUserId, request.getMessage());
        messagingTemplate.convertAndSend("/topic/room/" + roomId, msg);
    }
}
