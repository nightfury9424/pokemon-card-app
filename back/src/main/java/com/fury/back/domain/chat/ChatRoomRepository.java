package com.fury.back.domain.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ChatRoomRepository extends JpaRepository<ChatRoom, String> {

    Optional<ChatRoom> findBySaleListingIdAndBuyerUserId(String saleListingId, String buyerUserId);

    @Query("SELECT r FROM ChatRoom r WHERE r.sellerUserId = :userId OR r.buyerUserId = :userId ORDER BY COALESCE(r.lastMessageAt, r.createdAt) DESC")
    List<ChatRoom> findMyRooms(@Param("userId") String userId);

    /** Bundle 2-D: 1 trade ↔ N buyer 채팅방 모두 조회 — 상태 변경/삭제 시 시스템 메시지 fan-out용. */
    List<ChatRoom> findAllBySaleListingId(String saleListingId);
}
