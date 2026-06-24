package com.fury.back.domain.block;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.block.dto.BlockedUserDto;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.board.BoardTaxonomy;
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

    @Operation(summary = "사용자 차단")
    @PostMapping("/{userId}")
    @Transactional
    public ResponseEntity<ReturnData<Map<String, String>>> block(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String userId) {
        requireAuth(blockerId);
        return applyBlock(blockerId, userId);
    }

    @Operation(summary = "게시글 작성자 차단",
            description = "postId 로 작성자를 서버가 해석해 차단(raw authorId 미노출). 신고 없이 차단.")
    @PostMapping("/board-posts/{postId}")
    @Transactional
    public ResponseEntity<ReturnData<Map<String, String>>> blockPostAuthor(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String postId) {
        requireAuth(blockerId);
        BoardPost post = boardPostRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        if (BoardTaxonomy.isAdminType(post.getType())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "공식 게시글 작성자는 차단할 수 없습니다.");
        }
        return applyBlock(blockerId, post.getAuthorId());
    }

    @Operation(summary = "댓글 작성자 차단",
            description = "commentId 로 작성자를 서버가 해석해 차단(raw authorId 미노출). 신고 없이 차단.")
    @PostMapping("/board-comments/{commentId}")
    @Transactional
    public ResponseEntity<ReturnData<Map<String, String>>> blockCommentAuthor(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String commentId) {
        requireAuth(blockerId);
        BoardComment comment = boardCommentRepository.findById(commentId)
                .filter(c -> c.getDeletedAt() == null)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다."));
        // ★UI canBlock(forComment)=in && !mine && community 와 일치 — 부모 게시글이 존재·ACTIVE·미삭제·비공식인지
        //   서버 재검증(직접 호출 우회 차단). 운영자 댓글 작성자는 정책상 차단 허용(면제 없음).
        BoardPost post = boardPostRepository.findById(comment.getPostId())
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        if (BoardTaxonomy.isAdminType(post.getType())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "공식 게시글의 댓글은 차단할 수 없습니다.");
        }
        return applyBlock(blockerId, comment.getAuthorId());
    }

    /**
     * 공통 차단 처리 — self/blank 거부 + ★멱등(ON CONFLICT, 동시 요청에도 unique 위반 500 없이 1행) + 신규일 때만 notifyBlock.
     */
    private ResponseEntity<ReturnData<Map<String, String>>> applyBlock(String blockerId, String blockedId) {
        if (blockedId == null || blockedId.isBlank() || blockerId.equals(blockedId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "SELF_BLOCK");
        }
        String newId = IdGenerator.generate();
        boolean created = blockRepository.insertIgnoreBlock(newId, blockerId, blockedId) > 0;
        // Phase 1: 차단한 사람 hidden_at 자동 set + 차단당한 사람 방에 SYSTEM 메시지 1회.
        // 신규 차단일 때만 수행 (idempotent — 재호출 시 중복 SYSTEM 메시지 방지). board 작성자=채팅방 없으면 no-op.
        if (created) {
            chatService.notifyBlock(blockerId, blockedId);
        }
        String blockId = created ? newId
                : blockRepository.findByBlockerIdAndBlockedId(blockerId, blockedId)
                        .map(Block::getBlockId).orElse(newId);
        HttpStatus status = created ? HttpStatus.CREATED : HttpStatus.OK;
        return ResponseEntity.status(status)
                .body(ReturnData.success(Map.of("blockId", blockId)));
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
