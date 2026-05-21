package com.fury.back.domain.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, String> {

    List<ChatMessage> findByChatRoomIdOrderByCreatedAtAsc(String chatRoomId);

    long countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(String chatRoomId, String userId);

    /** affected rows return — Bundle 1 G1: 실제 read 갱신 시에만 STOMP broadcast 분기용. */
    @Modifying
    @Query("UPDATE ChatMessage m SET m.isRead = true WHERE m.chatRoomId = :roomId AND m.senderUserId != :userId AND m.isRead = false")
    int markAllAsRead(@Param("roomId") String roomId, @Param("userId") String userId);
}
