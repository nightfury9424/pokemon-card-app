package com.fury.back.domain.block;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(
        name = "blocks",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_blocks_blocker_blocked",
                columnNames = {"blocker_id", "blocked_id"}
        )
)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Block {

    @Id
    @Column(name = "block_id", length = 50)
    private String blockId;

    @Column(name = "blocker_id", nullable = false, length = 50)
    private String blockerId;

    @Column(name = "blocked_id", nullable = false, length = 50)
    private String blockedId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
