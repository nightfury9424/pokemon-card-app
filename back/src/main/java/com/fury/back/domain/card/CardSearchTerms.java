package com.fury.back.domain.card;

import java.util.Map;

/**
 * 카드/세트 검색어 정규화 + 별칭(canonicalize) — /cards/search 와 /cards/market 이 동일 기준을 쓰도록 공통화.
 *
 * <p>처리 순서: trim → lowercase → 공백·구분자({@code _ · 「」 -}) 제거 → 별칭 맵으로 흔한 오타만 교정.
 * Repository 는 컬럼(카드명/세트 고유명)에 <b>동일한</b> 정규화(regexp_replace)를 적용한 뒤
 * {@code LIKE '%canonical%'} 로 부분일치한다. 따라서 양쪽 정규화 기준이 반드시 일치해야 한다
 * (이 클래스의 {@link #DELIMITERS} = Repository 의 {@code '[[:space:]_·「」-]'}).
 *
 * <p>별칭은 <b>정규화된 key</b> 기준의 명시적 치환만 한다(전역 fuzzy/편집거리 확장 금지 — 오탐 방지).
 * 지금은 코드 상수 최소 별칭. 후속으로 {@code product_search_aliases} 테이블 / {@code products.search_aliases}
 * 로 분리해 운영에서 관리 가능하게 만든다.
 */
public final class CardSearchTerms {

    private CardSearchTerms() {}

    /**
     * 제거 집합 = Repository 컬럼 정규화({@code '[[:space:]_·「」-]'}) + LIKE 안전용 {@code % \}.
     * 카드/세트명엔 {@code % \ _} 가 없어 컬럼 정규화엔 불필요 — 검색어에서만 제거해
     * {@code LIKE '%' || :name || '%'} 패턴에 와일드카드/이스케이프 주입(`%`→전량 매칭)을 막는다
     * ({@code _} 는 이미 구분자로 제거됨). 따라서 정규화된 검색어는 LIKE 특수문자를 갖지 않는다.
     */
    private static final String DELIMITERS = "[\\s_·「」%\\\\-]";

    /** 정규화된 검색어 기준 별칭(흔한 오타만). 후속: DB(product_search_aliases) 로 이관. */
    private static final Map<String, String> ALIASES = Map.of(
            "인페리노", "인페르노"   // 흔한 오타 → 공식명 「인페르노X」 (인페리노/인페리노X/인페리노 X 전부 흡수)
    );

    /**
     * 검색어를 정규화·canonicalize 한다. null/공백/구분자만 입력이면 빈 문자열을 돌려준다
     * (호출부에서 빈 검색어를 browse/거부로 처리).
     */
    public static String canonicalize(String raw) {
        if (raw == null) return "";
        String n = raw.trim().toLowerCase().replaceAll(DELIMITERS, "");
        for (Map.Entry<String, String> e : ALIASES.entrySet()) {
            n = n.replace(e.getKey(), e.getValue());
        }
        return n;
    }
}
