package com.fury.back.domain.board;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.fury.back.auth.JwtUtil;
import com.fury.back.common.GlobalExceptionHandler;
import com.fury.back.common.moderation.ContentPolicyService;
import com.fury.back.common.moderation.ContentPolicyViolationException;
import com.fury.back.common.moderation.ModerationExceptionHandler;
import com.fury.back.domain.board.dto.BoardCommentDto;
import com.fury.back.domain.board.dto.BoardPageDto;
import com.fury.back.domain.board.dto.BoardPostDetailDto;
import com.fury.back.domain.board.dto.BoardPostSummaryDto;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.converter.json.MappingJackson2HttpMessageConverter;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * 게시판 컨트롤러 — standalone MockMvc(스프링 컨텍스트/보안 무관, 신뢰성↑).
 * GlobalExceptionHandler 등록으로 ResponseStatusException → 실제 400/404 매핑 검증.
 */
class BoardControllerTest {

    private BoardService service;
    private BoardWriteService writeService;
    private JwtUtil jwtUtil;
    private MockMvc mvc;

    @BeforeEach
    void setUp() {
        service = Mockito.mock(BoardService.class);
        writeService = Mockito.mock(BoardWriteService.class);
        jwtUtil = Mockito.mock(JwtUtil.class);
        ObjectMapper om = new ObjectMapper().registerModule(new JavaTimeModule());
        mvc = MockMvcBuilders.standaloneSetup(new BoardController(service, writeService, jwtUtil))
                // ★ModerationExceptionHandler 를 먼저 등록 — 더 구체적 예외(ContentPolicyViolationException)가
                //   GlobalExceptionHandler 의 catch(Exception) 보다 우선 매핑되는지 실제 요청으로 검증.
                .setControllerAdvice(new ModerationExceptionHandler(), new GlobalExceptionHandler())
                .setMessageConverters(new MappingJackson2HttpMessageConverter(om))
                .build();
    }

    @Test
    void createPost_bannedWord_returns_403_with_CONTENT_POLICY_VIOLATION() throws Exception {
        when(jwtUtil.isValid("tok")).thenReturn(true);
        when(jwtUtil.extractUserId("tok")).thenReturn("u1");
        doThrow(new ContentPolicyViolationException(ContentPolicyService.VIOLATION_MESSAGE))
                .when(writeService).createPost(eq("u1"), any());

        mvc.perform(post("/api/board/posts")
                        .header("Authorization", "Bearer tok")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"type\":\"free\",\"title\":\"t\",\"content\":\"x\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.status").value("fail"))
                .andExpect(jsonPath("$.code").value("CONTENT_POLICY_VIOLATION"))
                .andExpect(jsonPath("$.message").value(ContentPolicyService.VIOLATION_MESSAGE));
        // writeService.createPost 가 예외를 던져 저장 단계로 진행하지 않음(컨트롤러는 save 호출 경로 없음).
    }

    @Test
    void bannedWord_403_even_when_global_advice_registered_first() throws Exception {
        // ★Gate 1: 등록 순서를 일부러 Global 먼저로 뒤집어도 @Order(HIGHEST_PRECEDENCE) 로 Moderation 우선 →
        //   403 유지(등록 순서 의존이 아님을 증명).
        ObjectMapper om = new ObjectMapper().registerModule(new JavaTimeModule());
        MockMvc reversed = MockMvcBuilders.standaloneSetup(new BoardController(service, writeService, jwtUtil))
                .setControllerAdvice(new GlobalExceptionHandler(), new ModerationExceptionHandler())
                .setMessageConverters(new MappingJackson2HttpMessageConverter(om))
                .build();
        when(jwtUtil.isValid("tok")).thenReturn(true);
        when(jwtUtil.extractUserId("tok")).thenReturn("u1");
        doThrow(new ContentPolicyViolationException(ContentPolicyService.VIOLATION_MESSAGE))
                .when(writeService).createPost(eq("u1"), any());

        reversed.perform(post("/api/board/posts")
                        .header("Authorization", "Bearer tok")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"type\":\"free\",\"title\":\"t\",\"content\":\"x\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("CONTENT_POLICY_VIOLATION"));
    }

    private BoardPageDto onePage() {
        return new BoardPageDto(List.of(new BoardPostSummaryDto(
                "pp", "notice", "제목", "본문", "운영팀",
                LocalDateTime.of(2026, 6, 23, 10, 0), 0, 0, true, false, 0,
                false, false, false, false, false)), 0, 20, 1, 1);
    }

    @Test
    void list_anonymous_calls_service_with_null_viewer_and_200() throws Exception {
        when(service.getFeed(isNull(), isNull(), isNull(), eq(0), eq(20))).thenReturn(onePage());

        mvc.perform(get("/api/board/posts"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("pp")));

        verify(service).getFeed(null, null, null, 0, 20);
        verifyNoInteractions(jwtUtil); // 헤더 없으면 jwt 미호출
    }

    @Test
    void list_loggedIn_passes_viewerId() throws Exception {
        when(jwtUtil.isValid("tok")).thenReturn(true);
        when(jwtUtil.extractUserId("tok")).thenReturn("u1");
        when(service.getFeed(any(), any(), eq("u1"), anyInt(), anyInt())).thenReturn(onePage());

        mvc.perform(get("/api/board/posts").header("Authorization", "Bearer tok"))
                .andExpect(status().isOk());

        verify(service).getFeed(null, null, "u1", 0, 20);
    }

    @Test
    void list_badRequest_maps_to_400() throws Exception {
        when(service.getFeed(any(), any(), any(), anyInt(), anyInt()))
                .thenThrow(new ResponseStatusException(HttpStatus.BAD_REQUEST, "섹션과 타입이 일치하지 않습니다."));

        mvc.perform(get("/api/board/posts").param("section", "community").param("type", "qna"))
                .andExpect(status().isBadRequest());
    }

    // ── JSON 계약: 소유권·액션 플래그가 응답에 내려오고 authorId 는 노출 안 됨 ──
    @Test
    void detail_json_exposes_flags_and_hides_authorId() throws Exception {
        LocalDateTime t = LocalDateTime.of(2026, 6, 24, 10, 0);
        BoardCommentDto comment = new BoardCommentDto(
                "c1", "닉네임", "댓글본문", t, false, false, List.of(),
                true, true, true, "c1", false, false); // 본인 최상위 댓글
        BoardPostDetailDto detail = new BoardPostDetailDto(
                "pp", "free", "제목", "본문", "글쓴이", t, 0, 0, false, false, 1, List.of(comment),
                true, true, true, false, false); // 본인 자유글
        when(service.getDetail(eq("pp"), any())).thenReturn(detail);

        mvc.perform(get("/api/board/posts/pp"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.mine").value(true))
                .andExpect(jsonPath("$.data.canEdit").value(true))
                .andExpect(jsonPath("$.data.canDelete").value(true))
                .andExpect(jsonPath("$.data.canReport").value(false))
                .andExpect(jsonPath("$.data.canBlock").value(false))
                .andExpect(jsonPath("$.data.authorId").doesNotExist())
                .andExpect(jsonPath("$.data.comments[0].mine").value(true))
                .andExpect(jsonPath("$.data.comments[0].canDelete").value(true))
                .andExpect(jsonPath("$.data.comments[0].canReply").value(true))
                .andExpect(jsonPath("$.data.comments[0].replyTargetCommentId").value("c1"))
                .andExpect(jsonPath("$.data.comments[0].canReport").value(false))
                .andExpect(jsonPath("$.data.comments[0].canBlock").value(false))
                .andExpect(jsonPath("$.data.comments[0].authorId").doesNotExist());
    }

    @Test
    void list_json_exposes_post_flags() throws Exception {
        when(service.getFeed(any(), any(), any(), anyInt(), anyInt())).thenReturn(onePage());
        mvc.perform(get("/api/board/posts"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.content[0].mine").value(false))
                .andExpect(jsonPath("$.data.content[0].canEdit").value(false))
                .andExpect(jsonPath("$.data.content[0].canDelete").value(false))
                .andExpect(jsonPath("$.data.content[0].canReport").value(false))
                .andExpect(jsonPath("$.data.content[0].canBlock").value(false))
                .andExpect(jsonPath("$.data.content[0].authorId").doesNotExist());
    }

    @Test
    void detail_notFound_maps_to_404() throws Exception {
        when(service.getDetail(eq("x"), any()))
                .thenThrow(new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));

        mvc.perform(get("/api/board/posts/x"))
                .andExpect(status().isNotFound());
    }
}
