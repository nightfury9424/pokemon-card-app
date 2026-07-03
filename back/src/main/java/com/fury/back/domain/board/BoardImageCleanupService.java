package com.fury.back.domain.board;

import com.fury.back.storage.ImageStorageService;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 만료된 PENDING 임시 업로드(게시글 미연결) 정리.
 * ★순서: 조회 → S3 삭제 → S3 성공 시에만 DB 행 삭제 → 실패 시 행 유지 + 경고 로그(다음 주기 재시도).
 * DB 행부터 지워 추적 불가능한 S3 고아 객체를 만들지 않는다. CONSUMED/게시글 이미지는 대상 아님(보존).
 */
@Service
@RequiredArgsConstructor
public class BoardImageCleanupService {

    private static final Logger log = LoggerFactory.getLogger(BoardImageCleanupService.class);

    private final BoardImageUploadRepository uploadRepository;
    private final ImageStorageService imageStorageService;

    @Transactional
    public int cleanupExpiredPending() {
        List<BoardImageUpload> expired = uploadRepository
                .findTop200ByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(BoardImageUpload.PENDING, LocalDateTime.now());
        int deleted = 0;
        for (BoardImageUpload u : expired) {
            try {
                imageStorageService.delete(u.getStorageKey()); // S3 먼저
            } catch (Exception e) {
                log.warn("[BoardImageCleanup] S3 삭제 실패 — DB 행 유지(다음 주기 재시도): key={} err={}",
                        u.getStorageKey(), e.getMessage());
                continue; // ★DB 행부터 지우지 않음
            }
            uploadRepository.delete(u); // S3 성공 후에만
            deleted++;
        }
        return deleted;
    }
}
