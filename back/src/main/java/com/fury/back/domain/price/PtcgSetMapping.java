package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "ptcg_set_mappings")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PtcgSetMapping {

    @Id
    @Column(name = "product_id", length = 50)
    private String productId;

    // pokemontcg.io set ID (예: swsh12pt5, sv4pt5 ...)
    @Column(name = "ptcg_set_id", nullable = false, length = 50)
    private String ptcgSetId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
