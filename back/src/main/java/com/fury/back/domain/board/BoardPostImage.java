package com.fury.back.domain.board;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/** 게시글에 연결된 이미지(순서). storage_key = S3 키(전체 URL 아님). sort_order 0..4(최대 5장). */
@Entity
@Table(name = "board_post_images")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BoardPostImage {

    @Id
    @Column(name = "image_id", length = 50)
    private String imageId;

    @Column(name = "post_id", nullable = false, length = 50)
    private String postId;

    @Column(name = "storage_key", nullable = false, columnDefinition = "TEXT")
    private String storageKey;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;
}
