package com.fury.back.domain.block.dto;

import com.fury.back.domain.block.Block;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class BlockedUserDto {
    private String blockedId;
    private LocalDateTime blockedAt;

    public static BlockedUserDto from(Block block) {
        return BlockedUserDto.builder()
                .blockedId(block.getBlockedId())
                .blockedAt(block.getCreatedAt())
                .build();
    }
}
