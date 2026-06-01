package com.fury.back.storage;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectRequest;
import software.amazon.awssdk.services.s3.model.HeadObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

import jakarta.annotation.PostConstruct;
import java.io.IOException;
import java.io.InputStream;
import java.util.UUID;

/**
 * Phase 1-7: S3ImageStorageService — AWS S3 (또는 S3-compatible MinIO/R2).
 *
 * 활성 조건: app.image-storage.type=s3
 *
 * 정책:
 *   - private bucket (Public Access Block all on)
 *   - 외부 URL 노출 X — ImageProxyController가 stream
 *   - DB에는 storage key만 저장 ("uploads/trade/{tradeId}/{uuid}.jpg")
 */
@Slf4j
@Component
@ConditionalOnProperty(name = "app.image-storage.type", havingValue = "s3")
public class S3ImageStorageService implements ImageStorageService {

    private final S3Client s3;
    private final String bucket;

    public S3ImageStorageService(S3Client s3, @Value("${aws.s3.bucket}") String bucket) {
        this.s3 = s3;
        this.bucket = bucket;
    }

    @PostConstruct
    public void init() {
        if (bucket == null || bucket.isBlank()) {
            throw new IllegalStateException(
                    "AWS_S3_BUCKET must be set when app.image-storage.type=s3.");
        }
        log.info("[S3ImageStorage] bucket={}", bucket);
    }

    @Override
    public String store(String prefix, String origFilename, MultipartFile file) throws IOException {
        String ext = extractExt(origFilename);
        String filename = UUID.randomUUID().toString().replace("-", "") + ext;
        String key = normalizePrefix(prefix) + "/" + filename;

        PutObjectRequest req = PutObjectRequest.builder()
                .bucket(bucket)
                .key(key)
                .contentType(file.getContentType() != null ? file.getContentType() : "application/octet-stream")
                .contentLength(file.getSize())
                .build();

        try (InputStream in = file.getInputStream()) {
            s3.putObject(req, RequestBody.fromInputStream(in, file.getSize()));
        }
        log.debug("[S3ImageStorage] put bucket={} key={} size={}", bucket, key, file.getSize());
        return key;
    }

    @Override
    public InputStream load(String key) {
        return s3.getObject(
                GetObjectRequest.builder().bucket(bucket).key(key).build()
        );
    }

    @Override
    public String contentType(String key) {
        try {
            HeadObjectResponse head = s3.headObject(
                    HeadObjectRequest.builder().bucket(bucket).key(key).build()
            );
            String ct = head.contentType();
            return ct != null ? ct : "application/octet-stream";
        } catch (Exception e) {
            return "application/octet-stream";
        }
    }

    @Override
    public void delete(String key) {
        s3.deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(key).build());
    }

    @Override
    public boolean exists(String key) {
        try {
            s3.headObject(HeadObjectRequest.builder().bucket(bucket).key(key).build());
            return true;
        } catch (NoSuchKeyException e) {
            return false;
        } catch (Exception e) {
            log.warn("[S3ImageStorage] head failed key={}: {}", key, e.getMessage());
            return false;
        }
    }

    private String normalizePrefix(String prefix) {
        if (prefix == null || prefix.isBlank()) return "";
        String p = prefix.startsWith("/") ? prefix.substring(1) : prefix;
        return p.endsWith("/") ? p.substring(0, p.length() - 1) : p;
    }

    private String extractExt(String filename) {
        if (filename == null) return "";
        int idx = filename.lastIndexOf('.');
        if (idx < 0) return "";
        String ext = filename.substring(idx).toLowerCase();
        return ext.matches("\\.[a-z0-9]{1,5}") ? ext : "";
    }
}
