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

    /** 거래 list 카드별 batch count — N+1 방지. 각 row = [saleListingId, count]. */
    @Query("SELECT cr.saleListingId, COUNT(cr) FROM ChatRoom cr WHERE cr.saleListingId IN :tradeIds GROUP BY cr.saleListingId")
    List<Object[]> countBySaleListingIdIn(@Param("tradeIds") List<String> tradeIds);

    /** 단건 — 거래 상세 chatCount용. */
    long countBySaleListingId(String saleListingId);
}
