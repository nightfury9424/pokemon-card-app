package com.fury.back.domain.chat;

import com.fury.back.common.ApiResponse;
import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
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

    // 채팅방 입장 (없으면 생성)
    @PostMapping("/rooms")
    public ApiResponse<ChatRoomDto> enterRoom(
            @RequestBody Map<String, String> body,
            @AuthenticationPrincipal String userId) {
        String saleListingId = body.get("saleListingId");
        return ApiResponse.ok(chatService.getOrCreateRoom(saleListingId, userId));
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
