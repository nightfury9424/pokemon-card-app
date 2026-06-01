package com.fury.back.domain.trade;

/**
 * 호가창 1단 chip 상태 (2026-05-18: PSA/BRG 등급은 별도 param으로 분리).
 *
 * <p>UI chip 단위: RAW / PSA / BRG. CGC/BGS 미지원.
 *
 * <p>PSA/BRG 선택 시 2단 등급 chip [10] [9]로 추가 좁힘. 등급은 {@code grade} query param.
 *
 * <p>DB 매핑:
 * <ul>
 *   <li>RAW = card_status='RAW'</li>
 *   <li>PSA = card_status='GRADED' AND grading_company='PSA' (+ grade_value)</li>
 *   <li>BRG = card_status='GRADED' AND grading_company='BRG' (+ grade_value)</li>
 * </ul>
 */
public enum HogaStatus {
    RAW,
    PSA,
    BRG;

    public String dbCardStatus() {
        return this == RAW ? "RAW" : "GRADED";
    }

    /** null 이면 grading_company 무관(=RAW 케이스). */
    public String dbGradingCompany() {
        return switch (this) {
            case RAW -> null;
            case PSA -> "PSA";
            case BRG -> "BRG";
        };
    }

    /** 이 status가 별도 grade param을 요구하는지. */
    public boolean requiresGrade() {
        return this == PSA || this == BRG;
    }
}
