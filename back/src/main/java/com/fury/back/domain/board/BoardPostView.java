package com.fury.back.domain.board;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import java.io.Serializable;
import java.time.LocalDateTime;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;

/**
 * 게시글 조회 기록. (post_id, viewer_id) 복합 PK = 계정별 게시글당 1행(1인 1조회).
 * 실제 조회수 증가는 BoardViewService 가 INSERT(ON CONFLICT DO NOTHING) 성공 시에만 수행.
 * (JPA 엔티티로 둬 citest create-drop 스키마 생성 + ddl validate 일관성 확보. 운영 FK/CASCADE 는 마이그가 추가.)
 */
@Entity
@Table(name = "board_post_views")
@IdClass(BoardPostView.Pk.class)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BoardPostView {

    @Id
    @Column(name = "post_id", length = 50)
    private String postId;

    @Id
    @Column(name = "viewer_id", length = 50)
    private String viewerId;

    @Column(name = "viewed_at", nullable = false)
    private LocalDateTime viewedAt;

    @PrePersist
    void onCreate() {
        if (viewedAt == null) viewedAt = LocalDateTime.now();
    }

    @Getter
    @NoArgsConstructor
    @AllArgsConstructor
    @EqualsAndHashCode
    public static class Pk implements Serializable {
        private String postId;
        private String viewerId;
    }
}
