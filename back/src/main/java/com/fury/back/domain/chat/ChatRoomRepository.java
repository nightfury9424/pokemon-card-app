package com.fury.back.domain.chat;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface ChatRoomRepository extends JpaRepository<ChatRoom, String> {

    Optional<ChatRoom> findBySaleListingIdAndBuyerUserId(String saleListingId, String buyerUserId);

    /**
     * Phase 1: 본인의 hidden_at 이 null 인 방만 노출.
     * 나가기 / 차단 시 hidden_at set 되면 본인 목록에서 사라짐. DB 보존 — 관리자 조회 가능.
     */
    @Query("""
            SELECT r FROM ChatRoom r
            WHERE (r.buyerUserId = :userId AND r.buyerHiddenAt IS NULL)
               OR (r.sellerUserId = :userId AND r.sellerHiddenAt IS NULL)
            ORDER BY COALESCE(r.lastMessageAt, r.createdAt) DESC
            """)
    List<ChatRoom> findMyRooms(@Param("userId") String userId);

    /** Bundle 2-D: 1 trade ↔ N buyer 채팅방 모두 조회 — 상태 변경/삭제 시 시스템 메시지 fan-out용. */
    List<ChatRoom> findAllBySaleListingId(String saleListingId);

    /**
     * Phase 1: 두 사용자 사이 모든 채팅방 (buyer/seller 어느 쪽이든).
     * 차단 시 SYSTEM 메시지 fan-out + 차단한 사람 hidden_at set 용.
     */
    @Query("""
            SELECT r FROM ChatRoom r
            WHERE (r.buyerUserId = :u1 AND r.sellerUserId = :u2)
               OR (r.buyerUserId = :u2 AND r.sellerUserId = :u1)
            """)
    List<ChatRoom> findAllBetweenUsers(@Param("u1") String u1, @Param("u2") String u2);

    /** 거래 list 카드별 batch count — N+1 방지. 각 row = [saleListingId, count]. */
    @Query("SELECT cr.saleListingId, COUNT(cr) FROM ChatRoom cr WHERE cr.saleListingId IN :tradeIds GROUP BY cr.saleListingId")
    List<Object[]> countBySaleListingIdIn(@Param("tradeIds") List<String> tradeIds);

    /** 단건 — 거래 상세 chatCount용. */
    long countBySaleListingId(String saleListingId);
}
