package com.fury.back.domain.block;

import com.fury.back.BackApplication;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.board.BoardService;
import com.fury.back.domain.board.BoardTaxonomy;
import com.fury.back.domain.chat.ChatService;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpStatus;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 게시판 대상 차단 — postId/commentId 로 작성자를 서버가 해석해 차단(raw authorId 미노출). citest 실 PostgreSQL.
 * ChatService 는 @MockitoBean(board 작성자=채팅방 없음, hook 격리).
 */
@SpringBootTest(classes = BackApplication.class)
@ActiveProfiles("citest")
@Transactional
class BoardBlockTest {

    @Autowired BlockController blockController;
    @Autowired BlockRepository blockRepository;
    @Autowired BoardPostRepository boardPostRepository;
    @Autowired BoardCommentRepository boardCommentRepository;
    @Autowired BoardService boardService;
    @Autowired EntityManager em;
    @MockitoBean ChatService chatService;

    private BoardPost post(String id, String type, String authorId, boolean deleted) {
        return BoardPost.builder().postId(id).type(type).section(BoardTaxonomy.sectionOf(type))
                .title("글").content("본문").authorId(authorId).answered(false).viewCount(0).likeCount(0)
                .status("ACTIVE").createdAt(LocalDateTime.now())
                .deletedAt(deleted ? LocalDateTime.now() : null).build();
    }

    private BoardComment comment(String id, String postId, String authorId, boolean deleted) {
        return BoardComment.builder().commentId(id).postId(postId).authorId(authorId).content("댓글")
                .createdAt(LocalDateTime.now()).deletedAt(deleted ? LocalDateTime.now() : null).build();
    }

    @Test
    void blockPostAuthor_resolvesAuthor_created_thenIdempotent() {
        boardPostRepository.save(post("p1", "free", "author1", false));
        em.flush();
        var r1 = blockController.blockPostAuthor("viewer1", "p1");
        assertThat(r1.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(blockRepository.existsByBlockerIdAndBlockedId("viewer1", "author1")).isTrue();
        var r2 = blockController.blockPostAuthor("viewer1", "p1"); // 재호출 = idempotent
        assertThat(r2.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(blockRepository.findAllByBlockerId("viewer1")).hasSize(1); // 중복 row 없음
    }

    @Test
    void blockPostAuthor_self_badRequest() {
        boardPostRepository.save(post("p1", "free", "author1", false));
        em.flush();
        assertThatThrownBy(() -> blockController.blockPostAuthor("author1", "p1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test
    void blockPostAuthor_official_badRequest() {
        boardPostRepository.save(post("n1", "notice", "admin1", false));
        em.flush();
        assertThatThrownBy(() -> blockController.blockPostAuthor("viewer1", "n1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test
    void blockPostAuthor_deletedOrMissing_notFound() {
        boardPostRepository.save(post("pD", "free", "author1", true)); // soft-deleted
        em.flush();
        assertThatThrownBy(() -> blockController.blockPostAuthor("viewer1", "pD"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
        assertThatThrownBy(() -> blockController.blockPostAuthor("viewer1", "nope"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test
    void blockCommentAuthor_resolvesAuthor_created() {
        boardPostRepository.save(post("p1", "free", "author1", false));
        boardCommentRepository.save(comment("c1", "p1", "author2", false));
        em.flush();
        var r = blockController.blockCommentAuthor("viewer1", "c1");
        assertThat(r.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(blockRepository.existsByBlockerIdAndBlockedId("viewer1", "author2")).isTrue();
    }

    @Test
    void blockCommentAuthor_deletedOrMissing_notFound() {
        boardCommentRepository.save(comment("cD", "p1", "author2", true)); // 삭제 placeholder
        em.flush();
        assertThatThrownBy(() -> blockController.blockCommentAuthor("viewer1", "cD"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
        assertThatThrownBy(() -> blockController.blockCommentAuthor("viewer1", "nope"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test
    void blockCommentAuthor_parentPostDeletedOrMissing_notFound() {
        // 부모 게시글이 삭제됨 — 댓글 자체는 미삭제지만 차단 불가(직접 호출 우회 차단).
        boardPostRepository.save(post("pD", "free", "author1", true)); // deleted parent
        boardCommentRepository.save(comment("c1", "pD", "author2", false));
        boardCommentRepository.save(comment("c2", "pMissing", "author3", false)); // 부모 글 미존재
        em.flush();
        assertThatThrownBy(() -> blockController.blockCommentAuthor("viewer1", "c1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
        assertThatThrownBy(() -> blockController.blockCommentAuthor("viewer1", "c2"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test
    void blockCommentAuthor_parentPostOfficial_badRequest() {
        // 공식 게시글의 댓글(방어) — canBlock=false 정책(community 아님) 과 일치하게 거부.
        boardPostRepository.save(post("n1", "notice", "admin1", false));
        boardCommentRepository.save(comment("c1", "n1", "author2", false));
        em.flush();
        assertThatThrownBy(() -> blockController.blockCommentAuthor("viewer1", "c1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test
    void blockPostAuthor_repeatedIdempotent_singleRow() {
        // 순차 재호출 멱등 검증(1행 유지). 실제 동시 요청 안전성은 ON CONFLICT SQL 자체가 보장(이 테스트는 동시성 증명 아님).
        boardPostRepository.save(post("p1", "free", "author1", false));
        em.flush();
        blockController.blockPostAuthor("viewer1", "p1");
        blockController.blockPostAuthor("viewer1", "p1");
        blockController.blockPostAuthor("viewer1", "p1");
        assertThat(blockRepository.findAllByBlockerId("viewer1")).hasSize(1);
    }

    @Test
    void block_qnaNonAdminParent_allowed() {
        // qna = 비공식(non-admin) → forPost/forComment 의 canBlock 정책(community:=!isAdminType, BoardService:105)상
        // 차단 허용. UI 가 차단 버튼을 노출하므로 API 도 허용해야 함(isCommunityType 로 좁히면 UI-API 어긋남).
        boardPostRepository.save(post("q1", "qna", "author1", false));
        boardCommentRepository.save(comment("c1", "q1", "author2", false));
        em.flush();
        assertThat(blockController.blockPostAuthor("viewer1", "q1").getStatusCode())
                .isEqualTo(HttpStatus.CREATED); // qna 글 작성자 차단 허용
        assertThat(blockController.blockCommentAuthor("viewer1", "c1").getStatusCode())
                .isEqualTo(HttpStatus.CREATED); // qna 글의 댓글 작성자 차단 허용
        assertThat(blockRepository.existsByBlockerIdAndBlockedId("viewer1", "author1")).isTrue();
        assertThat(blockRepository.existsByBlockerIdAndBlockedId("viewer1", "author2")).isTrue();
    }

    @Test
    void afterBlock_feedExcludesAuthorPosts() {
        boardPostRepository.save(post("p1", "free", "author1", false));
        em.flush();
        assertThat(boardService.getFeed(null, "free", "viewer1", 0, 20).content())
                .extracting("id").contains("p1"); // 차단 전 보임
        blockController.blockPostAuthor("viewer1", "p1");
        em.flush();
        em.clear();
        assertThat(boardService.getFeed(null, "free", "viewer1", 0, 20).content())
                .extracting("id").doesNotContain("p1"); // 차단 후 제외
    }

    @Test
    void response_hasOnlyBlockId_noRawAuthorId() {
        boardPostRepository.save(post("p1", "free", "author1", false));
        em.flush();
        var body = blockController.blockPostAuthor("viewer1", "p1").getBody();
        assertThat(body.getData()).containsOnlyKeys("blockId"); // authorId 미노출
    }
}
