package com.fury.back.domain.block;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.block.dto.BlockedUserDto;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.domain.board.BoardPermissions;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.chat.ChatService;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.transaction.Transactional;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

@Tag(name = "Block", description = "사용자 차단")
@RestController
@RequestMapping("/api/blocks")
@RequiredArgsConstructor
public class BlockController {

    private final BlockRepository blockRepository;
    private final ChatService chatService;
    private final UserRepository userRepository;
    private final BoardPostRepository boardPostRepository;
    private final BoardCommentRepository boardCommentRepository;
    private final BlockService blockService;
    private final AdminAuthorizationService adminAuthorizationService;

    @Operation(summary = "사용자 차단")
    @PostMapping("/{userId}")
    public ResponseEntity<ReturnData<Map<String, String>>> block(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String userId) {
        requireAuth(blockerId);
        return toResponse(blockService.block(blockerId, userId)); // 트랜잭션은 BlockService 경계
    }

    @Operation(summary = "게시글 작성자 차단",
            description = "postId 로 작성자를 서버가 해석해 차단(raw authorId 미노출). 신고 없이 차단.")
    @PostMapping("/board-posts/{postId}")
    public ResponseEntity<ReturnData<Map<String, String>>> blockPostAuthor(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String postId) {
        requireAuth(blockerId);
        // 존재·ACTIVE·미삭제 재검증(직접 호출 우회 차단).
        BoardPost post = boardPostRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        // ★공통 판정(autoBlock·UI canBlock 과 동일) — 공식글 타입 OR 운영팀 작성자(자유글 포함)면 차단 금지.
        if (!BoardPermissions.canBlockPostAuthor(blockerId, post.getAuthorId(), post.getType(),
                adminAuthorizationService.isAdmin(post.getAuthorId()))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "운영팀 작성자는 차단할 수 없습니다.");
        }
        return toResponse(blockService.block(blockerId, post.getAuthorId()));
    }

    @Operation(summary = "댓글 작성자 차단",
            description = "commentId 로 작성자를 서버가 해석해 차단(raw authorId 미노출). 신고 없이 차단.")
    @PostMapping("/board-comments/{commentId}")
    public ResponseEntity<ReturnData<Map<String, String>>> blockCommentAuthor(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String commentId) {
        requireAuth(blockerId);
        BoardComment comment = boardCommentRepository.findById(commentId)
                .filter(c -> c.getDeletedAt() == null)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다."));
        // 부모 게시글 존재·ACTIVE·미삭제 재검증(삭제/숨김 글 댓글의 직접 호출 우회 차단).
        boardPostRepository.findById(comment.getPostId())
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        // ★공통 판정 — 차단 가능 여부는 부모글 타입이 아니라 ★댓글 작성자 기준. 공식글의 일반 사용자 댓글은 차단 가능,
        //   운영팀이 쓴 댓글(comment.isAdmin OR allowlist)만 차단 불가.
        if (!BoardPermissions.canBlockCommentAuthor(blockerId, comment.getAuthorId(), comment.isAdmin(),
                adminAuthorizationService.isAdmin(comment.getAuthorId()))) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "운영팀 댓글 작성자는 차단할 수 없습니다.");
        }
        return toResponse(blockService.block(blockerId, comment.getAuthorId()));
    }

    /** BlockResult → 응답(신규=201, 기존=200). */
    private ResponseEntity<ReturnData<Map<String, String>>> toResponse(BlockService.BlockResult r) {
        HttpStatus status = r.created() ? HttpStatus.CREATED : HttpStatus.OK;
        return ResponseEntity.status(status)
                .body(ReturnData.success(Map.of("blockId", r.blockId())));
    }

    @Operation(summary = "사용자 차단 해제")
    @DeleteMapping("/{userId}")
    @Transactional
    public ReturnData<Void> unblock(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String userId) {
        requireAuth(blockerId);
        // Phase 1 hotfix#3: 실제 row가 있을 때만 SYSTEM 메시지 (idempotent 중복 방지).
        boolean existed = blockRepository.existsByBlockerIdAndBlockedId(blockerId, userId);
        blockRepository.deleteByBlockerIdAndBlockedId(blockerId, userId);
        if (existed) {
            chatService.notifyUnblock(blockerId, userId);
        }
        return ReturnData.success();
    }

    @Operation(summary = "내 차단 목록")
    @GetMapping("/me")
    public ReturnData<List<BlockedUserDto>> getMine(@AuthenticationPrincipal String blockerId) {
        requireAuth(blockerId);
        List<Block> blocks = blockRepository.findAllByBlockerId(blockerId);
        // Phase 1 hotfix: nickname/profileImageUrl 함께. raw user_id 노출 X.
        List<String> userIds = blocks.stream().map(Block::getBlockedId).distinct().toList();
        Map<String, User> userMap = userRepository.findAllById(userIds).stream()
                .collect(java.util.stream.Collectors.toMap(User::getUserId, u -> u));
        return ReturnData.success(blocks.stream()
                .map(b -> BlockedUserDto.from(b, userMap.get(b.getBlockedId())))
                .toList());
    }

    private void requireAuth(String userId) {
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "AUTH_REQUIRED");
        }
    }
}
