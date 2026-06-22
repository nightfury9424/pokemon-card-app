package com.fury.back.domain.board;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.board.dto.AdminCreatePostRequest;
import com.fury.back.domain.board.dto.AdminUpdatePostRequest;
import com.fury.back.domain.board.dto.PostModerationRequest;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

/**
 * 게시판 관리자 API (Slice 2). 공식글 CRUD + 사용자글/댓글 모더레이션.
 * `/api/admin/**` → AdminAllowlistFilter 게이트 + BoardAdminService 서비스 재검증(이중).
 */
@Tag(name = "BoardAdmin", description = "게시판 (관리자)")
@RestController
@RequestMapping("/api/admin/board")
@RequiredArgsConstructor
public class BoardAdminController {

    private final BoardAdminService boardAdminService;
    private final JwtUtil jwtUtil;

    @Operation(summary = "공식글 작성", description = "notice/event/patch 만. author=서버결정(관리자).")
    @PostMapping("/posts")
    public ReturnData<Map<String, String>> create(
            @RequestBody AdminCreatePostRequest req, HttpServletRequest request) {
        String adminUserId = requireUserId(request);
        return ReturnData.success(Map.of("postId", boardAdminService.createOfficial(adminUserId, req)));
    }

    @Operation(summary = "공식글 수정", description = "공식글만 내용 수정 가능(사용자 글 내용수정 불가).")
    @PatchMapping("/posts/{postId}")
    public ReturnData<Void> update(
            @PathVariable String postId, @RequestBody AdminUpdatePostRequest req, HttpServletRequest request) {
        boardAdminService.updateOfficial(requireUserId(request), postId, req);
        return ReturnData.success();
    }

    @Operation(summary = "게시글 삭제(모더레이션)")
    @DeleteMapping("/posts/{postId}")
    public ReturnData<Void> delete(@PathVariable String postId, HttpServletRequest request) {
        boardAdminService.deletePost(requireUserId(request), postId);
        return ReturnData.success();
    }

    @Operation(summary = "게시글 모더레이션", description = "action: HIDE/UNHIDE(status)·RESTORE(deleted_at NULL만).")
    @PatchMapping("/posts/{postId}/moderation")
    public ReturnData<Void> moderate(
            @PathVariable String postId, @RequestBody PostModerationRequest req, HttpServletRequest request) {
        boardAdminService.moderatePost(requireUserId(request), postId, req);
        return ReturnData.success();
    }

    @Operation(summary = "댓글 삭제(모더레이션)")
    @DeleteMapping("/comments/{commentId}")
    public ReturnData<Void> deleteComment(@PathVariable String commentId, HttpServletRequest request) {
        boardAdminService.deleteComment(requireUserId(request), commentId);
        return ReturnData.success();
    }

    @Operation(summary = "댓글 복구(모더레이션)")
    @PatchMapping("/comments/{commentId}/restore")
    public ReturnData<Void> restoreComment(@PathVariable String commentId, HttpServletRequest request) {
        boardAdminService.restoreComment(requireUserId(request), commentId);
        return ReturnData.success();
    }

    private String requireUserId(HttpServletRequest request) {
        String bearer = request.getHeader("Authorization");
        if (StringUtils.hasText(bearer) && bearer.startsWith("Bearer ")) {
            String token = bearer.substring(7);
            if (jwtUtil.isValid(token)) return jwtUtil.extractUserId(token);
        }
        throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "로그인이 필요합니다.");
    }
}
