package com.fury.back.domain.inquiry;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 고객 문의 — 기존 flutter_email_sender(메일) 방식 폐기, DB 저장 + 관리자 페이지 처리로 전환.
 */
@Entity
@Table(name = "inquiries")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Inquiry {

    @Id
    @Column(name = "inquiry_id", length = 50)
    private String inquiryId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    /** cardAddRequest / price / trade / account / bug / feature / etc */
    @Column(name = "category", nullable = false, length = 30)
    private String category;

    @Column(name = "title", nullable = false, length = 200)
    private String title;

    @Column(name = "content", nullable = false, columnDefinition = "TEXT")
    private String content;

    /** 답변 회신용 — 사용자 이메일(있으면). */
    @Column(name = "contact_email", length = 200)
    private String contactEmail;

    /** OPEN / ANSWERED / CLOSED */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    // ── 관리자 처리 ──
    @Column(name = "admin_reply", columnDefinition = "TEXT")
    private String adminReply;

    @Column(name = "replied_by", length = 50)
    private String repliedBy;

    @Column(name = "replied_at")
    private LocalDateTime repliedAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (status == null) status = "OPEN";
    }

    /** 관리자 답변 등록 → status ANSWERED + 메타 기록. */
    public void markAnswered(String reply, String adminUserId) {
        this.adminReply = reply;
        this.repliedBy = adminUserId;
        this.repliedAt = LocalDateTime.now();
        this.status = "ANSWERED";
    }

    public void markClosed() {
        this.status = "CLOSED";
    }
}
