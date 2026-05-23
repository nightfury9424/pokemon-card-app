package com.fury.back.domain.block;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.block.dto.BlockedUserDto;
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

    @Operation(summary = "사용자 차단")
    @PostMapping("/{userId}")
    @Transactional
    public ResponseEntity<ReturnData<Map<String, String>>> block(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String userId) {
        requireAuth(blockerId);
        if (blockerId.equals(userId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "SELF_BLOCK");
        }

        var existing = blockRepository.findByBlockerIdAndBlockedId(blockerId, userId);
        boolean created = existing.isEmpty();
        Block block = existing.orElseGet(() -> blockRepository.save(Block.builder()
                .blockId(IdGenerator.generate())
                .blockerId(blockerId)
                .blockedId(userId)
                .build()));
        // Phase 1: 차단한 사람 hidden_at 자동 set + 차단당한 사람 방에 SYSTEM 메시지 1회.
        // 신규 차단일 때만 수행 (idempotent — 재호출 시 중복 SYSTEM 메시지 방지).
        if (created) {
            chatService.notifyBlock(blockerId, userId);
        }
        HttpStatus status = created ? HttpStatus.CREATED : HttpStatus.OK;
        return ResponseEntity.status(status)
                .body(ReturnData.success(Map.of("blockId", block.getBlockId())));
    }

    @Operation(summary = "사용자 차단 해제")
    @DeleteMapping("/{userId}")
    @Transactional
    public ReturnData<Void> unblock(
            @AuthenticationPrincipal String blockerId,
            @PathVariable String userId) {
        requireAuth(blockerId);
        blockRepository.deleteByBlockerIdAndBlockedId(blockerId, userId);
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
