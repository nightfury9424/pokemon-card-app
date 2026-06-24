package com.fury.back.domain.board;

import com.fury.back.BackApplication;
import com.fury.back.domain.board.dto.BoardPostDetailDto;
import com.fury.back.domain.board.dto.CreatePostRequest;
import com.fury.back.domain.board.dto.UpdatePostRequest;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.*;

/**
 * 이미지 첨부 게시글 E2E 계약(citest 실 PostgreSQL): 생성(uploadId consume) → 상세(imageId·proxy url·sortOrder) →
 * 수정(받은 imageId로 유지·순서변경·일부제거) → 타 게시글 imageId 거부. raw 키 미노출·CONSUMED 전환 검증.
 */
@SpringBootTest(classes = BackApplication.class)
@ActiveProfiles("citest")
@Transactional
class BoardImageFlowTest {

    @Autowired BoardWriteService writeService;
    @Autowired BoardService boardService;
    @Autowired BoardImageUploadRepository uploadRepo;
    @Autowired EntityManager em;

    private String pendingUpload(String owner, String key) {
        String id = "up_" + key.replaceAll("[^a-zA-Z0-9]", "");
        uploadRepo.save(BoardImageUpload.builder().uploadId(id).uploaderId(owner).storageKey(key)
                .status("PENDING").createdAt(LocalDateTime.now()).expiresAt(LocalDateTime.now().plusHours(1)).build());
        return id;
    }

    @Test
    void create_detail_edit_reorder_remove() {
        String u1 = pendingUpload("user", "uploads/board/pending/a.jpg");
        String u2 = pendingUpload("user", "uploads/board/pending/b.jpg");

        // 1. 이미지 2장 첨부 게시글 생성
        String postId = writeService.createPost("user", new CreatePostRequest("free", "제목", "본문", List.of(u1, u2)));
        em.flush();
        em.clear();

        // 2. 상세 — imageId·proxy URL·sortOrder, raw 키 미노출
        BoardPostDetailDto d1 = boardService.getDetail(postId, "user");
        assertThat(d1.images()).hasSize(2);
        var i0 = d1.images().get(0);
        var i1 = d1.images().get(1);
        assertThat(i0.sortOrder()).isEqualTo(0);
        assertThat(i1.sortOrder()).isEqualTo(1);
        assertThat(i0.imageId()).isNotBlank();
        assertThat(i0.url()).startsWith("/api/images/secure/"); // secure proxy(JWT 게이트), 직접 S3 URL 아님
        assertThat(uploadRepo.findById(u1).orElseThrow().getStatus()).isEqualTo("CONSUMED"); // consume 됨

        // 3+4. 받은 imageId로 순서 뒤집어 수정(둘 다 유지)
        writeService.updatePost("user", postId, new UpdatePostRequest("제목", "본문",
                List.of(new UpdatePostRequest.ImageItem(i1.imageId(), null),
                        new UpdatePostRequest.ImageItem(i0.imageId(), null))));
        em.flush();
        em.clear();
        BoardPostDetailDto d2 = boardService.getDetail(postId, "user");
        assertThat(d2.images()).hasSize(2);
        assertThat(d2.images().get(0).url()).isEqualTo(i1.url()); // 순서 뒤집힘(이전 1번이 0번으로)
        assertThat(d2.images().get(1).url()).isEqualTo(i0.url());
        assertThat(d2.images().get(0).sortOrder()).isEqualTo(0);

        // 5. 일부 제거(0번째만 유지)
        writeService.updatePost("user", postId, new UpdatePostRequest("제목", "본문",
                List.of(new UpdatePostRequest.ImageItem(d2.images().get(0).imageId(), null))));
        em.flush();
        em.clear();
        BoardPostDetailDto d3 = boardService.getDetail(postId, "user");
        assertThat(d3.images()).hasSize(1);
        assertThat(d3.images().get(0).url()).isEqualTo(i1.url()); // 남은 것
    }

    @Test
    void edit_otherPostImageId_rejected() {
        String ua = pendingUpload("user", "uploads/board/pending/x.jpg");
        String postA = writeService.createPost("user", new CreatePostRequest("free", "A", "a", List.of(ua)));
        String postB = writeService.createPost("user", new CreatePostRequest("free", "B", "b", List.of()));
        em.flush();
        em.clear();
        String aImageId = boardService.getDetail(postA, "user").images().get(0).imageId();
        // postB 수정에 postA 의 imageId 사용 → 거부
        assertThatThrownBy(() -> writeService.updatePost("user", postB, new UpdatePostRequest("B", "b",
                List.of(new UpdatePostRequest.ImageItem(aImageId, null)))))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }
}
