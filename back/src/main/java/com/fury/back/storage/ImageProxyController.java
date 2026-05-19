package com.fury.back.storage;

import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.StreamingResponseBody;

import java.io.InputStream;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.concurrent.TimeUnit;

/**
 * Phase 1-7: 이미지 proxy endpoint.
 *
 * GET /api/images/secure/{key}
 *   - JWT 인증 필요 (SecurityConfig에서 user toggle로 강제)
 *   - key prefix allow-list 검증 (uploads/{trade,asset,grading,scan}/ 만 허용)
 *   - path traversal `..` 차단
 *   - ImageStorageService(Local 또는 S3) load → stream 반환
 *
 * URL 패턴 메모:
 *   - {key:.+} 매핑은 slash 포함 path에서 spec/구현체별 버그 가능성 있음
 *   - 안전하게 `/**` + HttpServletRequest.getRequestURI()에서 prefix 이후 path 직접 추출
 */
@Slf4j
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/images/secure")
public class ImageProxyController {

    private static final String URI_PREFIX = "/api/images/secure/";

    /** 허용된 storage key prefix — 그 외 경로는 403. */
    private static final Set<String> ALLOWED_PREFIXES = Set.of(
            "uploads/trade/",
            "uploads/asset/",
            "uploads/grading/",
            "uploads/scan/"
    );

    private final ImageStorageService imageStorageService;

    @GetMapping("/**")
    public ResponseEntity<StreamingResponseBody> get(HttpServletRequest request) {
        String uri = request.getRequestURI();
        int idx = uri.indexOf(URI_PREFIX);
        if (idx < 0) {
            log.warn("[ImageProxy] uri prefix not found: {}", uri);
            return ResponseEntity.badRequest().build();
        }
        String rawKey = uri.substring(idx + URI_PREFIX.length());
        String key = URLDecoder.decode(rawKey, StandardCharsets.UTF_8);

        if (key.isBlank()) {
            log.warn("[ImageProxy] blank key uri={}", uri);
            return ResponseEntity.badRequest().build();
        }
        // path traversal / 비정상 경로 차단
        if (key.contains("..") || key.contains("//") || key.startsWith("/")) {
            log.warn("[ImageProxy] suspicious key blocked: {}", key);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }
        // prefix allow-list
        boolean allowed = ALLOWED_PREFIXES.stream().anyMatch(key::startsWith);
        if (!allowed) {
            log.warn("[ImageProxy] disallowed key prefix: {}", key);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
        }

        if (!imageStorageService.exists(key)) {
            log.warn("[ImageProxy] key not found in storage: {}", key);
            return ResponseEntity.notFound().build();
        }
        log.info("[ImageProxy] serve key={}", key);

        String contentType = imageStorageService.contentType(key);
        MediaType mt;
        try {
            mt = MediaType.parseMediaType(contentType);
        } catch (Exception e) {
            mt = MediaType.APPLICATION_OCTET_STREAM;
        }

        StreamingResponseBody body = out -> {
            try (InputStream in = imageStorageService.load(key)) {
                in.transferTo(out);
            }
        };

        return ResponseEntity.ok()
                .contentType(mt)
                .cacheControl(CacheControl.maxAge(1, TimeUnit.HOURS).cachePrivate())
                .body(body);
    }
}
