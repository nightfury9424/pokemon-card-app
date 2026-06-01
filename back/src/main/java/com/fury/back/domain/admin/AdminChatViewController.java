package com.fury.back.domain.admin;

import com.fury.back.common.ApiResponse;
import com.fury.back.domain.chat.ChatMessage;
import com.fury.back.domain.chat.ChatMessageRepository;
import com.fury.back.domain.chat.ChatRoom;
import com.fury.back.domain.chat.ChatRoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 신고 증거 — 관리자 챗방 메시지 조회. CHAT 신고의 targetId = chatRoomId.
 * /api/admin/** 아래라 AdminAllowlistFilter 자동 게이트(비-admin 403).
 */
@RestController
@RequestMapping("/api/admin/chat-rooms")
@RequiredArgsConstructor
public class AdminChatViewController {

    private final ChatRoomRepository chatRoomRepository;
    private final ChatMessageRepository chatMessageRepository;

    @GetMapping("/{roomId}/messages")
    public ApiResponse<Map<String, Object>> messages(@PathVariable String roomId) {
        ChatRoom room = chatRoomRepository.findById(roomId).orElse(null);
        List<ChatMessage> msgs = chatMessageRepository.findByChatRoomIdOrderByCreatedAtAsc(roomId);
        Map<String, Object> out = new HashMap<>();
        out.put("roomId", roomId);
        out.put("sellerUserId", room != null ? room.getSellerUserId() : null);
        out.put("buyerUserId", room != null ? room.getBuyerUserId() : null);
        out.put("messages", msgs);
        return ApiResponse.ok(out);
    }
}
