package com.fury.back.storage;

import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;

/**
 * Phase 1-7: 이미지 storage 추상화.
 *
 * 구현체:
 *   - LocalImageStorageService  (app.image-storage.type=local, default)
 *   - S3ImageStorageService     (app.image-storage.type=s3)
 *
 * 정책:
 *   - 저장 시 prefix는 도메인별 ({trade,asset,grading,scan}/{id}) 사용
 *   - returns storage key (DB에 저장. 공개 URL X)
 *   - 조회는 ImageProxyController 거쳐서 JWT 인증 후 stream
 */
public interface ImageStorageService {

    /**
     * prefix 아래에 file을 업로드하고 최종 storage key 반환.
     *
     * @param prefix       도메인 경로 (예: "uploads/trade/{tradeId}")
     * @param origFilename 원본 파일명 — 확장자 추출용
     * @param file         multipart file
     * @return key — DB에 저장할 값 (예: "uploads/trade/abc/uuid.jpg")
     */
    String store(String prefix, String origFilename, MultipartFile file) throws IOException;

    /** key 기반 stream load (proxy controller에서 사용). */
    InputStream load(String key) throws IOException;

    /** key의 content-type 반환 (proxy response header). */
    String contentType(String key);

    /** key 삭제 (TradePost/Asset 삭제 시 cleanup용, 베타에선 호출 X 가능). */
    void delete(String key) throws IOException;

    /** key 존재 여부. */
    boolean exists(String key);
}
