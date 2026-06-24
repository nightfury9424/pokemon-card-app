package com.fury.back.domain.board;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

import javax.imageio.ImageIO;
import javax.imageio.ImageReader;
import javax.imageio.stream.ImageInputStream;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.util.Iterator;

/**
 * 게시판 이미지 서버 검증 — 클라 image_picker 설정만 신뢰하지 않음.
 * 순서: 파일 크기 → 매직바이트(JPEG/PNG) → 헤더 width/height(전체 디코드 전) → 최대 해상도·총 픽셀 → 실제 디코드.
 * 위장/실행 파일·압축 폭탄(거대 해상도)을 전체 메모리 디코드 전에 거부.
 */
@Component
public class BoardImageValidator {

    private static final long MAX_FILE_BYTES = 10L * 1024 * 1024; // 10MB (multipart 제한과 일치)
    private static final int MAX_DIM = 4096;                      // 가로/세로 각각 상한
    private static final long MAX_PIXELS = 24_000_000L;           // 총 픽셀 상한(~24MP) — 폭탄 차단

    public record ValidatedImage(byte[] bytes, String ext, String contentType) {}

    public ValidatedImage validate(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw bad("이미지 파일이 비어 있습니다.");
        }
        if (file.getSize() > MAX_FILE_BYTES) {
            throw bad("이미지가 너무 큽니다(최대 10MB).");
        }
        final byte[] bytes;
        try {
            bytes = file.getBytes();
        } catch (IOException e) {
            throw bad("이미지를 읽지 못했습니다.");
        }
        if (bytes.length == 0 || bytes.length > MAX_FILE_BYTES) {
            throw bad("이미지가 너무 큽니다(최대 10MB).");
        }
        String fmt = sniffMagic(bytes);
        if (fmt == null) {
            throw bad("지원하지 않는 이미지 형식입니다(JPEG/PNG 만 허용).");
        }
        // 헤더 기반 width/height 확인(전체 디코드 전) → 해상도/픽셀 제한 → 실제 디코드.
        try (ImageInputStream iis = ImageIO.createImageInputStream(new ByteArrayInputStream(bytes))) {
            if (iis == null) {
                throw bad("이미지를 해석할 수 없습니다.");
            }
            Iterator<ImageReader> readers = ImageIO.getImageReaders(iis);
            if (!readers.hasNext()) {
                throw bad("이미지를 해석할 수 없습니다.");
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(iis, true, true);
                String rfmt = reader.getFormatName().toLowerCase();
                if (!rfmt.contains("jpeg") && !rfmt.contains("jpg") && !rfmt.contains("png")) {
                    throw bad("지원하지 않는 이미지 형식입니다(JPEG/PNG 만 허용).");
                }
                int w = reader.getWidth(0);
                int h = reader.getHeight(0);
                if (w <= 0 || h <= 0 || w > MAX_DIM || h > MAX_DIM || (long) w * h > MAX_PIXELS) {
                    throw bad("이미지 해상도가 너무 큽니다.");
                }
                BufferedImage img = reader.read(0); // 실제 디코드 — 위장/손상 파일 차단
                if (img == null) {
                    throw bad("이미지를 디코드할 수 없습니다.");
                }
            } finally {
                reader.dispose();
            }
        } catch (IOException e) {
            throw bad("이미지를 디코드할 수 없습니다.");
        }
        boolean png = "png".equals(fmt);
        return new ValidatedImage(bytes, png ? ".png" : ".jpg", png ? "image/png" : "image/jpeg");
    }

    /** 매직바이트 — JPEG(FF D8 FF) / PNG(89 50 4E 47 0D 0A 1A 0A). 확장자 신뢰 안 함. */
    private static String sniffMagic(byte[] b) {
        if (b.length >= 3 && (b[0] & 0xFF) == 0xFF && (b[1] & 0xFF) == 0xD8 && (b[2] & 0xFF) == 0xFF) {
            return "jpeg";
        }
        if (b.length >= 8 && (b[0] & 0xFF) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G'
                && (b[4] & 0xFF) == 0x0D && (b[5] & 0xFF) == 0x0A && (b[6] & 0xFF) == 0x1A && (b[7] & 0xFF) == 0x0A) {
            return "png";
        }
        return null;
    }

    private static ResponseStatusException bad(String msg) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, msg);
    }
}
