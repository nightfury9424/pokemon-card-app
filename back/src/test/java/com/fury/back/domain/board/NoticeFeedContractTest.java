package com.fury.back.domain.board;

import com.fury.back.BackApplication;
import com.fury.back.domain.board.dto.BoardPageDto;
import com.fury.back.domain.board.dto.BoardPostSummaryDto;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * ★홈 공지 배너 E2E 계약 — 실 PostgreSQL(citest) 에 공식 공지 저장 → 실 BoardService.getFeed("official","notice")
 * 가 배너가 읽는 BoardPostSummaryDto 필드(id/type/title/body 전문/isPinned/핀우선)를 그대로 서빙하는지 검증.
 * (관리자 작성→DB 는 BoardAdminServiceTest, DTO→JSON 직렬화는 BoardControllerTest, JSON→Flutter 파싱은
 * board_repository_parse_test 가 담당 → 본 테스트가 DB→feed 링크를 실DB로 닫아 루프를 완성.)
 */
@SpringBootTest(classes = BackApplication.class) // board 패키지의 슬라이스 config 와 충돌 회피 — 메인 앱 컨텍스트 명시
@ActiveProfiles("citest")
@Transactional
class NoticeFeedContractTest {

    @Autowired BoardPostRepository postRepository;
    @Autowired BoardPostImageRepository postImageRepository;
    @Autowired BoardService boardService;
    @Autowired EntityManager em;

    @Test
    void feedSummary_thumbnailIsSortZero_andImageCount() {
        postRepository.save(freePost("f-img"));
        postImageRepository.save(BoardPostImage.builder().imageId("im1").postId("f-img")
                .storageKey("uploads/board/k1.jpg").sortOrder(0).createdAt(LocalDateTime.now()).build());
        postImageRepository.save(BoardPostImage.builder().imageId("im2").postId("f-img")
                .storageKey("uploads/board/k2.jpg").sortOrder(1).createdAt(LocalDateTime.now()).build());
        postRepository.save(freePost("f-noimg"));
        em.flush();
        em.clear();

        BoardPageDto feed = boardService.getFeed("community", "free", null, 0, 20);
        var withImg = feed.content().stream().filter(s -> s.id().equals("f-img")).findFirst().orElseThrow();
        var noImg = feed.content().stream().filter(s -> s.id().equals("f-noimg")).findFirst().orElseThrow();
        // ★썸네일 = sort 0 의 secure proxy URL(raw 키 아님), imageCount = 총 첨부 수.
        assertThat(withImg.imageCount()).isEqualTo(2);
        assertThat(withImg.thumbnailUrl()).isEqualTo("/api/images/secure/uploads/board/k1.jpg");
        assertThat(noImg.imageCount()).isEqualTo(0);
        assertThat(noImg.thumbnailUrl()).isNull();
    }

    private BoardPost notice(String id, String title, String content, boolean pinned, LocalDateTime created) {
        return BoardPost.builder().postId(id).type("notice").section("official").title(title)
                .content(content).authorId("admin1").pinned(pinned).answered(false)
                .viewCount(0).likeCount(0).status("ACTIVE").createdAt(created).build();
    }

    private BoardPost freePost(String id) {
        return BoardPost.builder().postId(id).type("free").section("community").title("자유글")
                .content("x").authorId("u1").answered(false).viewCount(0).likeCount(0)
                .status("ACTIVE").createdAt(LocalDateTime.now()).build();
    }

    private BoardPost qnaPost(String id) {
        return BoardPost.builder().postId(id).type("qna").section("qna").title("질문글")
                .content("x").authorId("u1").answered(false).viewCount(0).likeCount(0)
                .status("ACTIVE").createdAt(LocalDateTime.now()).build();
    }

    @Test
    void officialNotice_db_to_feed_servesBannerContract() {
        postRepository.save(notice("n-old", "이전 공지", "이전 본문", false, LocalDateTime.now().minusDays(2)));
        postRepository.save(notice("n-pin", "고정 점검 공지", "점검 본문 전문입니다.", true, LocalDateTime.now().minusDays(1)));
        postRepository.save(freePost("f1")); // 자유글은 official/notice 피드에서 제외돼야
        em.flush();
        em.clear();

        BoardPageDto feed = boardService.getFeed("official", "notice", null, 0, 5);
        assertThat(feed.content()).hasSize(2); // 공지 2건만(자유글 제외)
        BoardPostSummaryDto first = feed.content().get(0);
        assertThat(first.isPinned()).isTrue();            // ★핀 우선
        assertThat(first.id()).isEqualTo("n-pin");
        assertThat(first.type()).isEqualTo("notice");
        assertThat(first.title()).isEqualTo("고정 점검 공지");
        assertThat(first.body()).isEqualTo("점검 본문 전문입니다."); // ★전문(축약 아님) — 배너/상세가 읽는 body
    }

    @Test
    void allFeed_excludesQna() {
        // ★전체 피드(section=null, type=null)는 qna 를 노출하지 않음 — board 노출 6타입만(qna 폐기).
        postRepository.save(freePost("f1"));
        postRepository.save(qnaPost("q1"));
        em.flush();
        em.clear();
        BoardPageDto feed = boardService.getFeed(null, null, null, 0, 20);
        assertThat(feed.content()).extracting("type").contains("free").doesNotContain("qna");
        assertThat(feed.content()).extracting("id").doesNotContain("q1");
    }

    @Test
    void adminEditTitle_reflectedInFeed() {
        BoardPost p = notice("n1", "원래 제목", "본문", false, LocalDateTime.now());
        postRepository.save(p);
        em.flush();
        p.adminEdit("수정된 제목", null, null); // 관리자 공지 수정과 동등
        postRepository.save(p);
        em.flush();
        em.clear();
        BoardPageDto feed = boardService.getFeed("official", "notice", null, 0, 5);
        assertThat(feed.content().get(0).title()).isEqualTo("수정된 제목");
    }

    @Test
    void pinToggle_reordersFeedFirst() {
        postRepository.save(notice("a", "공지 A(최신)", "x", false, LocalDateTime.now()));
        BoardPost b = notice("b", "공지 B(오래됨)", "x", false, LocalDateTime.now().minusDays(3));
        postRepository.save(b);
        em.flush();
        // 처음엔 최신(A)이 첫 항목
        assertThat(boardService.getFeed("official", "notice", null, 0, 5).content().get(0).id()).isEqualTo("a");
        // B 를 고정 → 핀 우선으로 B 가 첫 항목
        b.adminEdit(null, null, true);
        postRepository.save(b);
        em.flush();
        em.clear();
        assertThat(boardService.getFeed("official", "notice", null, 0, 5).content().get(0).id()).isEqualTo("b");
    }

    @Test
    void softDeletedNotice_excludedFromFeed() {
        BoardPost p = notice("n1", "삭제될 공지", "본문", false, LocalDateTime.now());
        postRepository.save(p);
        em.flush();
        p.softDelete();
        postRepository.save(p);
        em.flush();
        em.clear();
        assertThat(boardService.getFeed("official", "notice", null, 0, 5).content()).isEmpty(); // 배너 숨김 조건
    }

    @Test
    void noNotices_emptyFeed_bannerHidden() {
        postRepository.save(freePost("f1")); // 자유글만 존재
        em.flush();
        em.clear();
        assertThat(boardService.getFeed("official", "notice", null, 0, 5).content()).isEmpty();
    }
}
