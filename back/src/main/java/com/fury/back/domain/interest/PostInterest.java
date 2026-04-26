package com.fury.back.domain.interest;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "post_interests",
        uniqueConstraints = @UniqueConstraint(columnNames = {"user_id", "trade_id"}))
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PostInterest {

    @Id
    @Column(name = "interest_id", length = 50)
    private String interestId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "trade_id", nullable = false, length = 50)
    private String tradeId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
