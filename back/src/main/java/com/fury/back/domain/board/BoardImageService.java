package com.fury.back.domain.board;

import com.fury.back.common.IdGenerator;
import com.fury.back.storage.ImageStorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.LocalDateTime;

/** 게시판 이미지 업로드 — 검증 → S3(불투명 키) → board_image_uploads(PENDING) → uploadId. 소유권은 DB 로만. */
@Service
@RequiredArgsConstructor
public class BoardImageService {

    private static final String PENDING_PREFIX = "uploads/board/pending";
    private static final int MAX_PENDING_PER_USER = 10;
    private static final int RATE_WINDOW_SEC = 60;     // 빈도 제한 창
    private static final int MAX_PER_WINDOW = 20;       // 창당 최대 업로드
    private static final Duration TTL = Duration.ofHours(24);

    private final BoardImageUploadRepository uploadRepository;
    private final ImageStorageService imageStorageService;
    private final BoardImageValidator validator;

    @Transactional
    public String upload(String userId, MultipartFile file) {
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "로그인이 필요합니다.");
        }
        LocalDateTime now = LocalDateTime.now();
        // ★빈도 제한(S3 저장 전 거부) — 최근 RATE_WINDOW_SEC 초 업로드 수.
        if (uploadRepository.countByUploaderIdAndCreatedAtAfter(userId, now.minusSeconds(RATE_WINDOW_SEC)) >= MAX_PER_WINDOW) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "업로드가 너무 잦습니다. 잠시 후 다시 시도해 주세요.");
        }
        // ★활성 pending 개수 제한(만료분 제외, S3 저장 전 거부).
        if (uploadRepository.countByUploaderIdAndStatusAndExpiresAtAfter(userId, BoardImageUpload.PENDING, now) >= MAX_PENDING_PER_USER) {
            throw new ResponseStatusException(HttpStatus.TOO_MANY_REQUESTS,
                    "처리되지 않은 임시 이미지가 너무 많습니다. 게시글을 등록하거나 잠시 후 다시 시도해 주세요.");
        }
        BoardImageValidator.ValidatedImage v = validator.validate(file);

        String uploadId = IdGenerator.generate();
        String key;
        try {
            // store 가 자체 UUID 파일명 부여(prefix/{uuid}{ext}) → 불투명. ext 만 전달.
            key = imageStorageService.store(PENDING_PREFIX, "img" + v.ext(), v.bytes(), v.contentType());
        } catch (Exception e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "이미지 저장에 실패했습니다.");
        }
        try {
            uploadRepository.save(BoardImageUpload.builder()
                    .uploadId(uploadId)
                    .uploaderId(userId)
                    .storageKey(key)
                    .status(BoardImageUpload.PENDING)
                    .createdAt(now)
                    .expiresAt(now.plus(TTL))
                    .build());
        } catch (RuntimeException e) {
            // 보상: S3 저장 성공 후 DB insert 실패 → 고아 객체 best-effort 삭제.
            try {
                imageStorageService.delete(key);
            } catch (Exception ignore) {
                // 삭제 실패는 만료 정리 cron 이 처리(추적 가능하게 로그만).
            }
            throw e;
        }
        return uploadId;
    }
}
