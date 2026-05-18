package com.fury.back.domain.trade;

/**
 * 호가창 상태 필터 (1차: RAW / PSA10 / BRG).
 *
 * <p>UI chip 단위로 호가 데이터를 분리한다. CGC/BGS는 미지원 (2026-05-18 정책).
 *
 * <p>DB 매핑:
 * <ul>
 *   <li>RAW   = card_status='RAW'</li>
 *   <li>PSA10 = card_status='GRADED' AND grading_company='PSA' AND grade_value='10'</li>
 *   <li>BRG   = card_status='GRADED' AND grading_company='BRG' (grade_value 무관)</li>
 * </ul>
 */
public enum HogaStatus {
    RAW,
    PSA10,
    BRG;

    public String dbCardStatus() {
        return this == RAW ? "RAW" : "GRADED";
    }

    /** null 이면 grading_company 무관(=RAW 케이스). */
    public String dbGradingCompany() {
        return switch (this) {
            case RAW -> null;
            case PSA10 -> "PSA";
            case BRG -> "BRG";
        };
    }

    /** null 이면 grade_value 무관(=RAW, BRG 케이스). */
    public String dbGradeValue() {
        return this == PSA10 ? "10" : null;
    }
}
