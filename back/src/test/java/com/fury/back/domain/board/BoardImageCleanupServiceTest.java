package com.fury.back.domain.board;

import com.fury.back.storage.ImageStorageService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BoardImageCleanupServiceTest {

    @Mock BoardImageUploadRepository uploadRepo;
    @Mock ImageStorageService storage;
    @InjectMocks BoardImageCleanupService service;

    private BoardImageUpload up(String id, String key) {
        return BoardImageUpload.builder().uploadId(id).uploaderId("u").storageKey(key)
                .status("PENDING").createdAt(LocalDateTime.now().minusDays(2))
                .expiresAt(LocalDateTime.now().minusDays(1)).build();
    }

    @Test void cleanup_s3FirstThenDb_keepRowOnS3Fail() throws Exception {
        var ok = up("a", "k-a");
        var fail = up("b", "k-b");
        when(uploadRepo.findTop200ByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(any(), any()))
                .thenReturn(List.of(ok, fail));
        lenient().doThrow(new java.io.IOException("s3 down")).when(storage).delete("k-b"); // b = S3 실패(k-a 는 no-op)

        int n = service.cleanupExpiredPending();

        assertThat(n).isEqualTo(1);
        verify(uploadRepo).delete(ok);            // a: S3 성공 → DB 삭제
        verify(uploadRepo, never()).delete(fail); // ★b: S3 실패 → DB 행 유지(추적 가능, 재시도)
    }
}
