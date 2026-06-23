package com.fury.back.domain.board;

import org.junit.jupiter.api.Test;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 좋아요 Repository 통합 — 실제 Postgres(board_test). UNIQUE(post_id,user_id) + ON CONFLICT 멱등을
 * DB 레벨로 검증(스레드 병렬 대신 제약·ON CONFLICT 동작으로 동시성 대리 검증). 스키마는 board_post_likes 마이그 자동 적용.
 */
@SpringBootTest(classes = BoardPostLikeRepositoryTest.Cfg.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@ActiveProfiles("boardtest")
@Transactional
class BoardPostLikeRepositoryTest {

    // board 패키지 repo(BoardPostRepository.findFeed 등)가 Block 엔티티를 참조하므로 board+block 모두 스캔.
    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = {BoardPost.class, Block.class})
    @EnableJpaRepositories(basePackageClasses = {BoardPostRepository.class, BlockRepository.class})
    static class Cfg {}

    @Autowired BoardPostLikeRepository likes;

    @Test void insertIgnore_idempotent_and_count() {
        assertThat(likes.insertIgnore("L1", "P1", "U1")).isEqualTo(1); // 신규
        assertThat(likes.insertIgnore("L2", "P1", "U1")).isEqualTo(0); // ★중복 → ON CONFLICT no-op
        assertThat(likes.countByPostId("P1")).isEqualTo(1);
        assertThat(likes.existsByPostIdAndUserId("P1", "U1")).isTrue();
        assertThat(likes.existsByPostIdAndUserId("P1", "U2")).isFalse();
    }

    @Test void delete_idempotent() {
        likes.insertIgnore("L1", "P1", "U1");
        assertThat(likes.deleteByPostIdAndUserId("P1", "U1")).isEqualTo(1);
        assertThat(likes.deleteByPostIdAndUserId("P1", "U1")).isEqualTo(0); // 멱등 — 없던 것
        assertThat(likes.countByPostId("P1")).isEqualTo(0);
    }

    @Test void twoUsers_count_2() {
        likes.insertIgnore("L1", "P1", "U1");
        likes.insertIgnore("L2", "P1", "U2");
        assertThat(likes.countByPostId("P1")).isEqualTo(2);
    }

    @Test void bulk_count_and_liked_postIds() {
        likes.insertIgnore("L1", "P1", "U1");
        likes.insertIgnore("L2", "P1", "U2");
        likes.insertIgnore("L3", "P2", "U1");

        List<Object[]> counts = likes.countByPostIdIn(List.of("P1", "P2", "P3"));
        long p1 = counts.stream().filter(r -> r[0].equals("P1"))
                .mapToLong(r -> ((Number) r[1]).longValue()).findFirst().orElse(0);
        long p2 = counts.stream().filter(r -> r[0].equals("P2"))
                .mapToLong(r -> ((Number) r[1]).longValue()).findFirst().orElse(0);
        assertThat(p1).isEqualTo(2);
        assertThat(p2).isEqualTo(1);
        assertThat(counts.stream().anyMatch(r -> r[0].equals("P3"))).isFalse(); // 좋아요 0 → row 없음

        List<String> liked = likes.findLikedPostIds("U1", List.of("P1", "P2", "P3"));
        assertThat(liked).containsExactlyInAnyOrder("P1", "P2"); // U1 은 P1,P2 좋아요(P3 아님)
    }
}
