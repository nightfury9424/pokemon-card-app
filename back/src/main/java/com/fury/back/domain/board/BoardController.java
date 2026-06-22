package com.fury.back.domain.board;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.board.dto.BoardPageDto;
import com.fury.back.domain.board.dto.BoardPostDetailDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

/**
 * 게시판 읽기 API (Slice 1A). 목록/상세 조회만 — 작성·댓글등록·좋아요·신고는 이후 슬라이스.
 * 읽기는 공개. 토큰 있으면 viewerId 로 차단 author 제외(옵셔널).
 */
@Tag(name = "Board", description = "게시판 (읽기)")
@RestController
@RequestMapping("/api/board")
@RequiredArgsConstructor
public class BoardController {

    private final BoardService boardService;
    private final JwtUtil jwtUtil;

    @Operation(summary = "게시글 목록", description = "section/type 필터 + 페이지. 핀 우선 정렬.")
    @GetMapping("/posts")
    public ReturnData<BoardPageDto> list(
            @RequestParam(required = false) String section,
            @RequestParam(required = false) String type,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size,
            HttpServletRequest request) {
        String viewerId = optionalUserId(request);
        return ReturnData.success(boardService.getFeed(section, type, viewerId, page, size));
    }

    @Operation(summary = "게시글 상세", description = "댓글 트리(1단 답글) 포함. 미존재/삭제/숨김=404.")
    @GetMapping("/posts/{postId}")
    public ReturnData<BoardPostDetailDto> detail(
            @PathVariable String postId,
            HttpServletRequest request) {
        String viewerId = optionalUserId(request);
        return ReturnData.success(boardService.getDetail(postId, viewerId));
    }

    /** 공개 읽기 — 토큰 있으면 viewerId, 없으면 null(차단 필터 미적용). */
    private String optionalUserId(HttpServletRequest request) {
        String bearer = request.getHeader("Authorization");
        if (StringUtils.hasText(bearer) && bearer.startsWith("Bearer ")) {
            String token = bearer.substring(7);
            if (jwtUtil.isValid(token)) return jwtUtil.extractUserId(token);
        }
        return null;
    }
}
