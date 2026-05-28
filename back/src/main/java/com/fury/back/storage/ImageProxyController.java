package com.fury.back.storage;

import com.fury.back.domain.chat.ChatService;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
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

    /**
     * 2026-05-28: 채팅 이미지는 별도 검증 — prefix 통과만으로는 부족 (Codex O).
     * `chat/{roomId}/...` 패턴 + 요청자가 해당 room 의 참여자(buyer_user_id OR seller_user_id)일 때만 통과.
     */
    private static final String CHAT_PREFIX = "chat/";

    private final ImageStorageService imageStorageService;
    private final ChatService chatService;

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
        // 2026-05-28: chat/{roomId}/... 는 별도 participant 검증 (Codex O — 단순 allow-list 추가는 leak).
        if (key.startsWith(CHAT_PREFIX)) {
            String afterPrefix = key.substring(CHAT_PREFIX.length());
            int slash = afterPrefix.indexOf('/');
            if (slash <= 0) {
                log.warn("[ImageProxy] chat key malformed: {}", key);
                return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
            }
            String roomId = afterPrefix.substring(0, slash);
            String userId = currentUserId();
            if (userId == null) {
                log.warn("[ImageProxy] chat unauthenticated key={}", key);
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
            }
            if (!chatService.isRoomParticipant(roomId, userId)) {
                log.warn("[ImageProxy] chat non-participant userId={} roomId={}", userId, roomId);
                return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
            }
            // 참여자 통과 — load로 진행.
        } else {
            // 기존 uploads/* prefix allow-list (변경 없음).
            boolean allowed = ALLOWED_PREFIXES.stream().anyMatch(key::startsWith);
            if (!allowed) {
                log.warn("[ImageProxy] disallowed key prefix: {}", key);
                return ResponseEntity.status(HttpStatus.FORBIDDEN).build();
            }
        }

        // exists() 체크 제거 (IAM s3:HeadObject 누락 우회).
        // load()에서 NoSuchKey/NoSuchFileException catch → 404 처리.
        // contentType도 stream 미리 받은 후 byte 통째 buffer해서 일관 처리.
        final byte[] bytes;
        final String contentType;
        try (InputStream in = imageStorageService.load(key)) {
            bytes = in.readAllBytes();
            contentType = imageStorageService.contentType(key);
            log.info("[ImageProxy] serve key={} bytes={} content-type={}", key, bytes.length, contentType);
        } catch (software.amazon.awssdk.services.s3.model.NoSuchKeyException e) {
            log.warn("[ImageProxy] S3 NoSuchKey key={}", key);
            return ResponseEntity.notFound().build();
        } catch (java.nio.file.NoSuchFileException | java.io.FileNotFoundException e) {
            log.warn("[ImageProxy] local file not found key={} err={}", key, e.getMessage());
            return ResponseEntity.notFound().build();
        } catch (software.amazon.awssdk.services.s3.model.S3Exception e) {
            log.error("[ImageProxy] S3 error key={} status={} msg={}",
                    key, e.statusCode(), e.awsErrorDetails() != null ? e.awsErrorDetails().errorMessage() : e.getMessage());
            return ResponseEntity.status(e.statusCode() == 404 ? HttpStatus.NOT_FOUND : HttpStatus.INTERNAL_SERVER_ERROR).build();
        } catch (Exception e) {
            log.error("[ImageProxy] unexpected error key={} err={}", key, e.getMessage(), e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }

        MediaType mt;
        try {
            mt = MediaType.parseMediaType(contentType);
        } catch (Exception e) {
            mt = MediaType.APPLICATION_OCTET_STREAM;
        }

        StreamingResponseBody body = out -> out.write(bytes);

        return ResponseEntity.ok()
                .contentType(mt)
                .contentLength(bytes.length)
                .cacheControl(CacheControl.maxAge(1, TimeUnit.HOURS).cachePrivate())
                .body(body);
    }

    /** SecurityContext 에서 현재 userId (JwtAuthFilter 가 principal 로 String userId set). */
    private String currentUserId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) return null;
        Object principal = auth.getPrincipal();
        return principal instanceof String s ? s : null;
    }
}
