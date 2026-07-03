package com.fury.back.domain.board;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 게시글 이미지 임시 업로드(소유권·일회성·만료). 작성/수정 시 uploadId 검증(소유자·PENDING·미만료) 후
 * board_post_images 로 consume. 클라이언트가 raw storage_key 를 직접 연결하지 못하게 하는 소유권 계층.
 */
@Entity
@Table(name = "board_image_uploads")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BoardImageUpload {

    public static final String PENDING = "PENDING";
    public static final String CONSUMED = "CONSUMED";

    @Id
    @Column(name = "upload_id", length = 50)
    private String uploadId;

    @Column(name = "uploader_id", nullable = false, length = 50)
    private String uploaderId;

    @Column(name = "storage_key", nullable = false, columnDefinition = "TEXT")
    private String storageKey;

    @Column(name = "status", nullable = false, length = 20)
    private String status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @Column(name = "consumed_at")
    private LocalDateTime consumedAt;

    @Column(name = "consumed_post_id", length = 50)
    private String consumedPostId;

    public boolean isPending() {
        return PENDING.equals(status);
    }

    public boolean isExpired(LocalDateTime now) {
        return expiresAt.isBefore(now);
    }

    /** 게시글 연결 — PENDING → CONSUMED. 호출 전 isPending/isExpired 검증 필수. */
    public void consume(String postId, LocalDateTime at) {
        this.status = CONSUMED;
        this.consumedPostId = postId;
        this.consumedAt = at;
    }
}
