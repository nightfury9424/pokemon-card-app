package com.fury.back.domain.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, String> {

    List<ChatMessage> findByChatRoomIdOrderByCreatedAtAsc(String chatRoomId);

    long countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(String chatRoomId, String userId);

    @Modifying
    @Query("UPDATE ChatMessage m SET m.isRead = true WHERE m.chatRoomId = :roomId AND m.senderUserId != :userId AND m.isRead = false")
    void markAllAsRead(@Param("roomId") String roomId, @Param("userId") String userId);
}
