package com.fury.back.storage;

import com.fury.back.domain.chat.ChatService;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.io.ByteArrayInputStream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

/**
 * ★board 이미지 proxy allow-list 회귀 고정 — uploads/board/ 누락 시 게시판 이미지가 앱·Admin 에서 403 되던 버그 재발 방지.
 */
@ExtendWith(MockitoExtension.class)
class ImageProxyControllerTest {

    @Mock ImageStorageService imageStorageService;
    @Mock ChatService chatService;
    @InjectMocks ImageProxyController controller;

    private HttpServletRequest req(String uri) {
        HttpServletRequest r = mock(HttpServletRequest.class);
        when(r.getRequestURI()).thenReturn(uri);
        return r;
    }

    @Test
    void boardKey_allowed_andReachesLoad() throws Exception {
        final String key = "uploads/board/pending/abc.jpg";
        when(imageStorageService.load(key)).thenReturn(new ByteArrayInputStream(new byte[]{1, 2, 3}));
        when(imageStorageService.contentType(key)).thenReturn("image/jpeg");
        var resp = controller.get(req("/api/images/secure/" + key));
        assertThat(resp.getStatusCode().value()).isEqualTo(200);
        verify(imageStorageService).load(key); // ★board 이미지가 실제 load 로 전달
    }

    @Test
    void tradeKey_stillAllowed() throws Exception {
        when(imageStorageService.load(anyString())).thenReturn(new ByteArrayInputStream(new byte[]{1}));
        when(imageStorageService.contentType(anyString())).thenReturn("image/jpeg");
        var resp = controller.get(req("/api/images/secure/uploads/trade/t.jpg"));
        assertThat(resp.getStatusCode().value()).isEqualTo(200); // 기존 prefix 회귀 없음
    }

    @Test
    void disallowedPrefix_403_noLoad() {
        var resp = controller.get(req("/api/images/secure/uploads/secret/s.jpg"));
        assertThat(resp.getStatusCode().value()).isEqualTo(403);
        verifyNoInteractions(imageStorageService);
    }

    @Test
    void pathTraversal_403_noLoad() {
        var resp = controller.get(req("/api/images/secure/uploads/board/../trade/x.jpg"));
        assertThat(resp.getStatusCode().value()).isEqualTo(403);
        verifyNoInteractions(imageStorageService);
    }
}
