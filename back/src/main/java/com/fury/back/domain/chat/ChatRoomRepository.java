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
}
