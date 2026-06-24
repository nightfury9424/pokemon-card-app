package com.fury.back.domain.board;

import com.fury.back.storage.ImageStorageService;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BoardImageServiceTest {

    @Mock BoardImageUploadRepository uploadRepo;
    @Mock ImageStorageService storage;
    @Mock BoardImageValidator validator;
    @InjectMocks BoardImageService service;

    @Test void upload_dbInsertFails_s3Compensated() throws Exception {
        when(uploadRepo.countByUploaderIdAndStatus(any(), any())).thenReturn(0L);
        when(validator.validate(any()))
                .thenReturn(new BoardImageValidator.ValidatedImage(new byte[]{1}, ".jpg", "image/jpeg"));
        when(storage.store(any(), any(), any(byte[].class), any())).thenReturn("uploads/board/pending/k.jpg");
        when(uploadRepo.save(any())).thenThrow(new RuntimeException("db down"));
        assertThatThrownBy(() -> service.upload("u1", mock(MultipartFile.class)))
                .isInstanceOf(RuntimeException.class);
        verify(storage).delete("uploads/board/pending/k.jpg"); // ★보상: 고아 S3 객체 삭제
    }

    @Test void upload_tooManyPending_429() {
        when(uploadRepo.countByUploaderIdAndStatus(any(), any())).thenReturn(10L);
        assertThatThrownBy(() -> service.upload("u1", mock(MultipartFile.class)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("429");
        verifyNoInteractions(storage);
    }

    @Test void upload_unauthenticated_401() {
        assertThatThrownBy(() -> service.upload(null, mock(MultipartFile.class)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("401");
    }
}
