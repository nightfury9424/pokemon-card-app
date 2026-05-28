package com.fury.back.domain.chat;

import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.chat.dto.ConversationStateDto;

import java.util.List;

public interface ChatService {
    ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId);

    /**
     * 2026-05-28 BuyOrder 양방향 채팅 — 잠재 판매자(sellerUserId)가 BuyOrder 작성자에게 채팅 시작.
     * 자기 BuyOrder에는 채팅 불가 (self-chat 차단). DB UNIQUE(buy_order_id, seller_user_id) 보장.
     * 신규 방 생성 시 SYSTEM 환영/사기 주의 메시지 1회.
     */
    ChatRoomDto getOrCreateRoomFromBuyOrder(String buyOrderId, String sellerUserId);

    List<ChatRoomDto> getMyRooms(String userId);
    List<ChatMessageDto> getMessages(String roomId, String userId);
    ChatMessageDto sendMessage(String roomId, String senderUserId, String message);

    /**
     * 2026-05-28: 채팅 이미지 메시지 전송 — REST 업로드 + AFTER_COMMIT STOMP broadcast.
     * S3 store는 트랜잭션 밖에서 먼저 수행하고, DB save 실패 시 best-effort S3 delete (Codex P).
     *
     * @param roomId         채팅방 ID
     * @param senderUserId   업로더 user_id (room participant 여야 함)
     * @param file           MultipartFile — magic number 검증 + 10MB 제한 + MIME 화이트리스트
     * @return 저장된 IMAGE 메시지 DTO (message = proxy URL)
     */
    ChatMessageDto sendImageMessage(String roomId, String senderUserId,
                                    org.springframework.web.multipart.MultipartFile file);

    /**
     * 2026-05-28: 채팅 이미지 proxy 접근 시 participant 검증 — ImageProxyController 가 chat/{roomId}/...
     * key 요청 받았을 때 호출. participant 아니면 403.
     */
    boolean isRoomParticipant(String roomId, String userId);

    /**
     * Phase 1: 채팅방 나가기 — 본인의 hidden_at set. DB 보존, 본인 목록에서만 숨김.
     * 참여자 검증 후 buyer/seller 분기 자동.
     */
    void leaveRoom(String roomId, String userId);

    /**
     * Phase 1: 채팅방 진입 시 입력창/안내 상태 조회.
     * 차단 관계가 있으면 canSendMessage=false + blockNotice 문구 반환.
     */
    ConversationStateDto getConversationState(String roomId, String userId);

    /**
     * Phase 1: 차단 액션 hook — 두 사용자 사이 모든 방에 차단한 사람 hidden_at set
     * + 각 방에 "상대방의 설정으로 인해 더 이상 대화할 수 없습니다." SYSTEM 메시지 1회.
     * BlockController 가 차단 저장 후 호출.
     */
    void notifyBlock(String blockerId, String blockedId);

    /**
     * Phase 1 hotfix#3: 차단 해제 hook — 두 사용자 사이 모든 방에 SYSTEM "차단이 해제되었습니다.
     * 다시 대화할 수 있어요." 1회. AFTER_COMMIT STOMP broadcast → 양쪽 ChatRoomScreen이
     * SYSTEM 수신 hook으로 conversation-state 재조회 → 즉시 banner/입력 갱신.
     * BlockController.unblock 이 실제 row 삭제 시에만 호출 (idempotent 중복 방지).
     */
    void notifyUnblock(String blockerId, String unblockedId);

    /**
     * Bundle 1.5 (active read gap): 채팅방에 active 상태로 있을 때 새 메시지 도착 시
     * 즉시 read 처리용 lightweight endpoint. 메시지 리스트 반환 X.
     */
    void markRoomAsRead(String roomId, String userId);

    /**
     * Bundle 2-C: 시스템 메시지 전송 (sender_user_id='SYSTEM', message_type='SYSTEM').
     * 상태 변경/사기 주의 안내 등 자동 메시지에 사용.
     * AFTER_COMMIT 이벤트로 STOMP broadcast — 일반 메시지와 동일 topic에 push.
     */
    ChatMessageDto sendSystemMessage(String roomId, String content);

    /**
     * Bundle 2-D: trade 상태 변경 시 해당 trade의 모든 chat_room에 시스템 메시지 fan-out.
     * - 1 trade ↔ N buyer 패턴 (UNIQUE 정책상 same buyer 1방 보장, 다른 buyer 각각)
     * - sendSystemMessage 동일 인프라 활용 — AFTER_COMMIT broadcast
     */
    void broadcastTradeStatusChanged(String saleListingId, String newStatus);

    /**
     * 2026-05-28 BUY chat 용 — BuyOrder 상태 변경(CANCELED/MATCHED) 시 해당 BuyOrder의 모든 chat_room
     * 에 SYSTEM fan-out. broadcastTradeStatusChanged 와 의미는 같지만 BuyOrder.status 도메인이
     * OPEN/MATCHED/CANCELED 라 텍스트 분기가 다르므로 별도 메서드 (Codex G).
     */
    void broadcastBuyOrderStatusChanged(String buyOrderId, String newStatus);
}
