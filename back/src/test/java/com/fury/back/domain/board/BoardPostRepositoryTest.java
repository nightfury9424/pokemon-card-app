package com.fury.back.domain.board;

import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import jakarta.persistence.EntityManagerFactory;
import org.hibernate.SessionFactory;
import org.hibernate.stat.Statistics;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.persistence.autoconfigure.EntityScan;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Timestamp;
import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 게시판 읽기 Repository 검증 — 실제 Postgres(board_test) 사용(H2 dialect drift 회피).
 * Boot 4.0 은 @DataJpaTest 슬라이스를 별도 모듈로 분리(오프라인 미보유) → 캐시 의존성만으로
 * 최소 JPA 컨텍스트를 직접 구성. ddl-auto=none(스키마는 board_read/blocks 마이그 사전 적용).
 */
@SpringBootTest(classes = BoardPostRepositoryTest.JpaSliceConfig.class,
        webEnvironment = SpringBootTest.WebEnvironment.NONE)
@ActiveProfiles("boardtest")
@Transactional
class BoardPostRepositoryTest {

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @EntityScan(basePackageClasses = {BoardPost.class, Block.class})
    @EnableJpaRepositories(basePackageClasses = {BoardPostRepository.class, BlockRepository.class})
    static class JpaSliceConfig {}

    @Autowired BoardPostRepository posts;
    @Autowired BoardCommentRepository comments;
    @Autowired JdbcTemplate jdbc;
    @Autowired EntityManagerFactory emf;

    private static final LocalDateTime T1 = LocalDateTime.of(2026, 6, 23, 10, 0, 0);
    private static final LocalDateTime T2 = T1.plusMinutes(1);
    private static final LocalDateTime T3 = T1.plusMinutes(2);

    private BoardPost post(String id, String type, String section, String author,
                           boolean pinned, LocalDateTime created, String status, LocalDateTime deleted) {
        return BoardPost.builder()
                .postId(id).type(type).section(section).title("t-" + id).content("body")
                .authorId(author).pinned(pinned).answered(false).viewCount(0).likeCount(0)
                .status(status).createdAt(created).deletedAt(deleted).build();
    }

    private BoardComment comment(String id, String postId, String parent, String author,
                                 LocalDateTime created, LocalDateTime deleted) {
        return BoardComment.builder()
                .commentId(id).postId(postId).parentCommentId(parent).authorId(author)
                .content("c-" + id).admin(false).accepted(false).createdAt(created).deletedAt(deleted).build();
    }

    private void insertBlock(String blocker, String blocked) {
        jdbc.update("INSERT INTO blocks(block_id, blocker_id, blocked_id, created_at) VALUES (?,?,?,?)",
                blocker + "_" + blocked, blocker, blocked, Timestamp.valueOf(T1));
    }

    @Test
    void feed_filters_by_section_type_and_pins_first() {
        posts.saveAndFlush(post("pa", "free", "community", "u1", false, T2, "ACTIVE", null));
        posts.saveAndFlush(post("pb", "free", "community", "u2", true, T1, "ACTIVE", null)); // pinned, earlier
        posts.saveAndFlush(post("pc", "notice", "official", "u3", false, T3, "ACTIVE", null));
        posts.saveAndFlush(post("pd", "tradeReview", "community", "u4", false, T3, "ACTIVE", null)); // ★폐기타입 → 피드 제외

        Page<BoardPost> community = posts.findFeed("community", null, null, PageRequest.of(0, 10));
        assertThat(community.getContent()).extracting(BoardPost::getPostId)
                .containsExactly("pb", "pa"); // pinned first, then newer; pc(official)·pd(tradeReview) 제외

        Page<BoardPost> official = posts.findFeed("official", null, null, PageRequest.of(0, 10));
        assertThat(official.getContent()).extracting(BoardPost::getPostId).containsExactly("pc"); // 공지(official)
    }

    @Test
    void feed_excludes_deleted_and_hidden() {
        posts.saveAndFlush(post("p1", "free", "community", "u1", false, T1, "ACTIVE", null));
        posts.saveAndFlush(post("p2", "free", "community", "u1", false, T2, "ACTIVE", T2)); // soft-deleted
        posts.saveAndFlush(post("p3", "free", "community", "u1", false, T3, "HIDDEN", null)); // moderated

        Page<BoardPost> feed = posts.findFeed(null, null, null, PageRequest.of(0, 10));
        assertThat(feed.getContent()).extracting(BoardPost::getPostId).containsExactly("p1");
    }

    @Test
    void feed_excludes_blocked_author_only_for_viewer() {
        posts.saveAndFlush(post("px", "free", "community", "ax", false, T2, "ACTIVE", null));
        posts.saveAndFlush(post("py", "free", "community", "ay", false, T1, "ACTIVE", null));
        insertBlock("viewer", "ax");

        Page<BoardPost> asViewer = posts.findFeed(null, null, "viewer", PageRequest.of(0, 10));
        assertThat(asViewer.getContent()).extracting(BoardPost::getPostId).containsExactly("py");

        Page<BoardPost> anon = posts.findFeed(null, null, null, PageRequest.of(0, 10));
        assertThat(anon.getContent()).extracting(BoardPost::getPostId).containsExactly("px", "py");
    }

    @Test
    void feed_pagination_stable_on_equal_createdAt() {
        posts.saveAndFlush(post("p_a", "free", "community", "u1", false, T1, "ACTIVE", null));
        posts.saveAndFlush(post("p_b", "free", "community", "u1", false, T1, "ACTIVE", null));
        posts.saveAndFlush(post("p_c", "free", "community", "u1", false, T1, "ACTIVE", null));

        List<String> page0 = posts.findFeed(null, null, null, PageRequest.of(0, 2))
                .getContent().stream().map(BoardPost::getPostId).toList();
        List<String> page1 = posts.findFeed(null, null, null, PageRequest.of(1, 2))
                .getContent().stream().map(BoardPost::getPostId).toList();

        assertThat(page0).containsExactly("p_c", "p_b"); // post_id DESC tiebreak
        assertThat(page1).containsExactly("p_a");
        assertThat(page0).doesNotContainAnyElementsOf(page1);
    }

    @Test
    void comments_loaded_in_order_and_active_count() {
        posts.saveAndFlush(post("pp", "qna", "qna", "u1", false, T1, "ACTIVE", null));
        comments.saveAndFlush(comment("c1", "pp", null, "u2", T1, null));
        comments.saveAndFlush(comment("c2", "pp", null, "u3", T2, T2));   // deleted
        comments.saveAndFlush(comment("c3", "pp", "c1", "u4", T3, null)); // reply

        assertThat(comments.findByPostIdOrderByCreatedAtAsc("pp"))
                .extracting(BoardComment::getCommentId).containsExactly("c1", "c2", "c3");
        assertThat(comments.countByPostIdAndDeletedAtIsNull("pp")).isEqualTo(2);
        var counts = comments.countActiveByPostIds(List.of("pp"));
        assertThat(counts).hasSize(1);
        assertThat(counts.get(0).getCnt()).isEqualTo(2);
    }

    @Test
    void feed_query_count_is_constant_regardless_of_post_count() {
        // N+1 증명: 피드 쿼리 수가 게시글 수(5→20)에 따라 늘지 않음 + 댓글수 집계는 batch 1쿼리.
        Statistics stats = emf.unwrap(SessionFactory.class).getStatistics();

        for (int i = 0; i < 5; i++) {
            posts.saveAndFlush(post("a" + i, "free", "community", "u" + i, false, T1.plusSeconds(i), "ACTIVE", null));
        }
        stats.clear();
        posts.findFeed("community", null, null, PageRequest.of(0, 50)).getContent();
        long q5 = stats.getPrepareStatementCount();

        for (int i = 0; i < 15; i++) {
            posts.saveAndFlush(post("b" + i, "free", "community", "v" + i, false, T1.plusSeconds(100 + i), "ACTIVE", null));
        }
        stats.clear();
        List<BoardPost> content = posts.findFeed("community", null, null, PageRequest.of(0, 50)).getContent();
        long q20 = stats.getPrepareStatementCount();

        assertThat(content).hasSize(20);
        assertThat(q20).isEqualTo(q5);            // 게시글 수와 무관 → per-post 쿼리(N+1) 없음
        assertThat(q20).isLessThanOrEqualTo(2);   // 내용(+옵션 count) 만, per-row 0

        // 댓글수 집계도 게시글 N개에 대해 단일 IN 쿼리.
        stats.clear();
        comments.countActiveByPostIds(content.stream().map(BoardPost::getPostId).toList());
        assertThat(stats.getPrepareStatementCount()).isEqualTo(1);
    }
}
