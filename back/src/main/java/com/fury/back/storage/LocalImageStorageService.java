package com.fury.back.storage;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.UUID;

/**
 * Phase 1-7: LocalImageStorageService — disk 저장 (local/dev 편의).
 *
 * 활성 조건: app.image-storage.type=local (default, matchIfMissing=true).
 * base dir = ${app.image-storage.local.base-dir:${user.home}/pokefolio-uploads}
 *
 * 보안:
 *   - resolveSafe()로 path traversal (../) 차단
 *   - 저장 파일명은 UUID로 재할당 (orig filename 그대로 사용 X)
 */
@Slf4j
@Component
@ConditionalOnProperty(name = "app.image-storage.type", havingValue = "local", matchIfMissing = true)
public class LocalImageStorageService implements ImageStorageService {

    private final Path baseDir;

    public LocalImageStorageService(
            @Value("${app.image-storage.local.base-dir}") String baseDirStr) {
        this.baseDir = Paths.get(baseDirStr).toAbsolutePath().normalize();
    }

    @PostConstruct
    public void init() throws IOException {
        Files.createDirectories(baseDir);
        log.info("[LocalImageStorage] baseDir={}", baseDir);
    }

    @Override
    public String store(String prefix, String origFilename, MultipartFile file) throws IOException {
        String ext = extractExt(origFilename);
        String filename = UUID.randomUUID().toString().replace("-", "") + ext;
        String key = normalizePrefix(prefix) + "/" + filename;
        Path target = resolveSafe(key);
        Files.createDirectories(target.getParent());
        file.transferTo(target);
        log.debug("[LocalImageStorage] store key={} size={}", key, file.getSize());
        return key;
    }

    @Override
    public InputStream load(String key) throws IOException {
        Path resolved = resolveSafe(key);
        return Files.newInputStream(resolved);
    }

    @Override
    public String contentType(String key) {
        try {
            String probed = Files.probeContentType(resolveSafe(key));
            return probed != null ? probed : "application/octet-stream";
        } catch (IOException e) {
            return "application/octet-stream";
        }
    }

    @Override
    public void delete(String key) throws IOException {
        Files.deleteIfExists(resolveSafe(key));
    }

    @Override
    public boolean exists(String key) {
        try {
            return Files.exists(resolveSafe(key));
        } catch (Exception e) {
            return false;
        }
    }

    private Path resolveSafe(String key) {
        if (key == null || key.isBlank()) {
            throw new IllegalArgumentException("Empty storage key");
        }
        Path resolved = baseDir.resolve(key).normalize();
        if (!resolved.startsWith(baseDir)) {
            throw new IllegalArgumentException("Invalid key (path traversal): " + key);
        }
        return resolved;
    }

    private String normalizePrefix(String prefix) {
        if (prefix == null || prefix.isBlank()) return "";
        // leading/trailing slash 제거
        String p = prefix.startsWith("/") ? prefix.substring(1) : prefix;
        return p.endsWith("/") ? p.substring(0, p.length() - 1) : p;
    }

    private String extractExt(String filename) {
        if (filename == null) return "";
        int idx = filename.lastIndexOf('.');
        if (idx < 0) return "";
        String ext = filename.substring(idx).toLowerCase();
        // 확장자 sanitize: 영숫자 + dot만 허용
        return ext.matches("\\.[a-z0-9]{1,5}") ? ext : "";
    }
}
