package com.fury.back.domain.interest;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 카드 단위 관심 목록 — 사용자가 거래 리스트에서 하트 토글로 카드를 찜.
 * PostInterest(판매글 단위)와 별개. 거래 리스트는 카드 마켓이라 카드 단위가 자연.
 */
@Entity
@Table(name = "card_interests",
        uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "card_id"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class CardInterest {

    @Id
    @Column(name = "interest_id", length = 50)
    private String interestId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
