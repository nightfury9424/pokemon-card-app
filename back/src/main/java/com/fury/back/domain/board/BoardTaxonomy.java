package com.fury.back.domain.board;

import java.util.Map;
import java.util.Set;

/**
 * 게시판 type ↔ section 분류 (프론트 BoardType/BoardSection 와 동일 토큰).
 * - 관리자 작성 전용 타입: notice / event / patch
 * - 유저 작성 가능 타입: free / tradeReview / scamAlert / qna
 */
public final class BoardTaxonomy {

    private BoardTaxonomy() {}

    public static final String SECTION_OFFICIAL = "official";
    public static final String SECTION_COMMUNITY = "community";
    public static final String SECTION_QNA = "qna";

    /** type → section (결정적). */
    private static final Map<String, String> TYPE_TO_SECTION = Map.of(
            "notice", SECTION_OFFICIAL,
            "event", SECTION_OFFICIAL,
            "patch", SECTION_OFFICIAL,
            "free", SECTION_COMMUNITY,
            "tradeReview", SECTION_COMMUNITY,
            "scamAlert", SECTION_COMMUNITY,
            "qna", SECTION_QNA
    );

    private static final Set<String> ADMIN_TYPES = Set.of("notice", "event", "patch");
    private static final Set<String> SECTIONS = Set.of(SECTION_OFFICIAL, SECTION_COMMUNITY, SECTION_QNA);
    /** 일반 사용자가 작성 가능한 타입(공식·qna 제외). 작성 allowlist. */
    private static final Set<String> USER_WRITABLE_TYPES = Set.of("free", "tradeReview", "scamAlert");
    /** 게시판 UI 에 노출하는 타입(qna 제외). 전체 피드/탭은 이 6개만. */
    private static final Set<String> BOARD_VISIBLE_TYPES =
            Set.of("notice", "event", "patch", "free", "tradeReview", "scamAlert");

    public static boolean isValidType(String type) {
        return type != null && TYPE_TO_SECTION.containsKey(type);
    }

    public static boolean isValidSection(String section) {
        return section != null && SECTIONS.contains(section);
    }

    /** type 의 소속 section. 알 수 없는 type 이면 null. */
    public static String sectionOf(String type) {
        return TYPE_TO_SECTION.get(type);
    }

    /** type 이 section 에 속하는지(작성 검증 / 조회 필터 충돌 검증). */
    public static boolean typeBelongsToSection(String type, String section) {
        return section != null && section.equals(TYPE_TO_SECTION.get(type));
    }

    /** notice/event/patch = 운영팀 작성 → 표시명 고정. */
    public static boolean isAdminType(String type) {
        return type != null && ADMIN_TYPES.contains(type);
    }

    /** 일반 사용자 작성 허용 타입(free/tradeReview/scamAlert)만 true. 공식·qna 는 false → 작성 API allowlist. */
    public static boolean isUserWritableType(String type) {
        return type != null && USER_WRITABLE_TYPES.contains(type);
    }

    /** 게시판 노출 타입(qna 제외 6종)만 true. 전체 피드 필터용. */
    public static boolean isBoardVisibleType(String type) {
        return type != null && BOARD_VISIBLE_TYPES.contains(type);
    }
}
