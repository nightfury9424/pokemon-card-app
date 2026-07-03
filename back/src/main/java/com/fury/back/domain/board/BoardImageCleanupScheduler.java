package com.fury.back.domain.board;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/** 임시 이미지 만료 정리 cron. 기본 off — board.image-cleanup.enabled=true 일 때만 활성(prod 는 host cron 도 가능). */
@Component
@ConditionalOnProperty(name = "board.image-cleanup.enabled", havingValue = "true")
@RequiredArgsConstructor
public class BoardImageCleanupScheduler {

    private final BoardImageCleanupService cleanupService;

    @Scheduled(cron = "${board.image-cleanup.cron:0 30 4 * * *}") // 매일 04:30
    public void run() {
        cleanupService.cleanupExpiredPending();
    }
}
