package com.fury.back.storage;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * Phase 1-7: DB storage key ↔ API 응답 URL 변환 helper.
 *
 * 정책:
 *   - DB에는 storage key만 저장 (예: "uploads/trade/abc/uuid.jpg")
 *   - API 응답에는 /api/images/secure/{key} 형태로 변환
 *   - legacy 값 (예: "/images/trades/...", "http://...")은 변환 없이 그대로 통과 — 호환성
 */
public final class StorageKeyUrls {

    public static final String PROXY_PREFIX = "/api/images/secure/";

    private StorageKeyUrls() {}

    /**
     * storage key → proxy URL 변환.
     * - 이미 "/"로 시작하거나 "http"로 시작하는 값은 legacy → 그대로 반환
     * - 그 외에는 PROXY_PREFIX + key
     */
    public static String toProxyUrl(String stored) {
        if (stored == null || stored.isBlank()) return null;
        if (stored.startsWith("/") || stored.startsWith("http://") || stored.startsWith("https://")) {
            return stored;
        }
        return PROXY_PREFIX + stored;
    }

    /**
     * comma-separated stored 값들을 각각 변환 후 다시 comma join.
     */
    public static String toProxyCsv(String csv) {
        if (csv == null || csv.isBlank()) return null;
        return Arrays.stream(csv.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .map(StorageKeyUrls::toProxyUrl)
                .collect(Collectors.joining(","));
    }

    /**
     * csv에서 첫 url만 proxy 변환. 단일 url 필드 (호가 sheet thumbnail,
     * 채팅 헤더 trade 썸네일, 관심 카드 thumb) — 여러 사진 중 첫 장만 표시.
     */
    public static String firstProxyUrl(String csv) {
        if (csv == null || csv.isBlank()) return null;
        String[] parts = csv.split(",");
        if (parts.length == 0) return null;
        String first = parts[0].trim();
        if (first.isEmpty()) return null;
        return toProxyUrl(first);
    }
}
