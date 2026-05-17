package com.fury.back.domain.asset;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "asset_images")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class AssetImage {

    @Id
    @Column(name = "image_id", length = 50)
    private String imageId;

    @Column(name = "asset_id", nullable = false, length = 50)
    private String assetId;

    @Column(name = "image_type", nullable = false, length = 10)
    private String imageType;

    @Column(name = "image_url", nullable = false, columnDefinition = "TEXT")
    private String imageUrl;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    public static AssetImage of(String assetId, String imageType, String imageUrl) {
        return AssetImage.builder()
                .imageId(UUID.randomUUID().toString())
                .assetId(assetId)
                .imageType(imageType)
                .imageUrl(imageUrl)
                .build();
    }

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
