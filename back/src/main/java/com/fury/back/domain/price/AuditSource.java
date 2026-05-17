package com.fury.back.domain.price;

/**
 * KO_ESTIMATED audit의 selected_source 정규화 enum.
 * price_snapshots.source ('SCRYDEX_JP' 등)와 다른 값 공간 — audit 비교 일관성 보장.
 *
 * 변환 규칙은 fromSnapshotSource()로 통일. 직접 비교 시 source_changed 오판 위험.
 */
public enum AuditSource {
    JP,
    EN,
    KO_TRADE,
    PSA10_FALLBACK,
    PROMO_DIRECT,
    NONE;

    public static AuditSource fromSnapshotSource(String snapshotSource) {
        if (snapshotSource == null) return NONE;
        return switch (snapshotSource) {
            case "SCRYDEX_JP" -> JP;
            case "SCRYDEX_EN" -> EN;
            default -> NONE;
        };
    }

    /** 랭킹 후보 자격 — JP/EN만 (PSA10_FALLBACK/PROMO_DIRECT는 has_ko_trade_change=true일 때만 별도 허용) */
    public boolean isRankingCandidate() {
        return this == JP || this == EN;
    }
}
