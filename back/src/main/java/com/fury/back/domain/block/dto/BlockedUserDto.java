package com.fury.back.domain.block.dto;

import com.fury.back.domain.block.Block;
import com.fury.back.domain.user.User;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class BlockedUserDto {
    private String blockedId;
    private String blockedNickname;
    private String blockedProfileImageUrl;
    private LocalDateTime blockedAt;

    /** Phase 1 hotfix: User 매핑 받아서 nickname/profileImageUrl 함께. user 미존재 fallback null. */
    public static BlockedUserDto from(Block block, User user) {
        return BlockedUserDto.builder()
                .blockedId(block.getBlockedId())
                .blockedNickname(user != null ? user.getNickname() : null)
                .blockedProfileImageUrl(user != null ? user.getProfileImageUrl() : null)
                .blockedAt(block.getCreatedAt())
                .build();
    }
}
