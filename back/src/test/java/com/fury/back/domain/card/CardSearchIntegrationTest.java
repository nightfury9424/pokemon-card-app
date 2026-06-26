package com.fury.back.domain.card;

import com.fury.back.BackApplication;
import com.fury.back.domain.product.Product;
import com.fury.back.domain.product.ProductRepository;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * #15 카드 검색 세트명 매칭 — 실제 PostgreSQL(citest, create-drop) Repository→Service 통합.
 * 「」 고유명 매칭 + is_visible 필터(@SQLRestriction 보존) + 언어/중복/DTO 검증.
 */
@SpringBootTest(classes = BackApplication.class)
@ActiveProfiles("citest")
@Transactional
class CardSearchIntegrationTest {

    @Autowired CardRepository cardRepository;
    @Autowired ProductRepository productRepository;
    @Autowired CardService cardService;
    @Autowired EntityManager em;

    private static final LocalDateTime T = LocalDateTime.of(2026, 6, 26, 0, 0);

    private Product product(String id, String name) {
        return Product.builder().productId(id).name(name).language("KO").createdAt(T).updatedAt(T).build();
    }
    private Card card(String id, String productId, String name, String lang, boolean visible) {
        return Card.builder()
                .cardId(id).productId(productId).name(name).language(lang)
                .superType("Pokemon").isPromoExclusive(false).isVisible(visible)
                .rarityCode("AR") // market(rarity 필터) 테스트용 — 전부 고레어
                .createdAt(T).updatedAt(T).build();
    }

    @BeforeEach
    void setup() {
        productRepository.save(product("ABYSS", "MEGA 확장팩 「어비스아이」"));
        productRepository.save(product("LOST", "소드&실드 확장팩 「로스트어비스」"));
        productRepository.save(product("OTHER", "관계없는 세트"));
        cardRepository.save(card("a1", "ABYSS", "피카츄", "KO", true));
        cardRepository.save(card("a2", "ABYSS", "리자몽", "KO", true));
        cardRepository.save(card("a3", "ABYSS", "Pikachu", "EN", true));
        cardRepository.save(card("a4", "ABYSS", "숨김커먼", "KO", false)); // is_visible=false
        cardRepository.save(card("l1", "LOST", "뮤츠", "KO", true));
        cardRepository.save(card("o1", "OTHER", "메가다크라이", "KO", true)); // 카드명에 다크라이
        // 정규화/별칭 검증용: 인페르노(공백/오타) + 151(공백)
        productRepository.save(product("INFERNO", "MEGA 확장팩 「인페르노X」"));
        productRepository.save(product("P151", "강화 확장팩 「포켓몬 카드 151」 프로모 카드 팩"));
        cardRepository.save(card("i1", "INFERNO", "라우드본", "KO", true));
        cardRepository.save(card("i2", "INFERNO", "윈디", "KO", true));
        cardRepository.save(card("p1", "P151", "뮤", "KO", true));
        em.flush();
        em.clear();
    }

    @Test void abyssEye_onlyThatSet_excludesHidden() {
        var r = cardRepository.searchByCardNameOrProductName("어비스아이");
        assertThat(r).extracting(Card::getCardId).containsExactlyInAnyOrder("a1", "a2", "a3"); // a4 숨김 제외
    }

    @Test void abyss_returnsBothSets() {
        var r = cardRepository.searchByCardNameOrProductName("어비스");
        assertThat(r).extracting(Card::getCardId).contains("a1", "a2", "a3", "l1"); // 어비스아이 + 로스트어비스
    }

    @Test void cardName_darkrai_stillWorks() {
        var r = cardRepository.searchByCardNameOrProductName("다크라이");
        assertThat(r).extracting(Card::getCardId).containsExactly("o1"); // 카드명 검색 보존
    }

    @Test void language_KO_filtersKoOnly() {
        var r = cardRepository.searchByCardNameOrProductNameAndLanguage("어비스아이", "KO");
        assertThat(r).extracting(Card::getCardId).containsExactlyInAnyOrder("a1", "a2"); // EN a3·숨김 a4 제외
    }

    @Test void isVisible_filterPreserved() {
        var r = cardRepository.searchByCardNameOrProductName("어비스아이");
        assertThat(r).extracting(Card::getCardId).doesNotContain("a4"); // @SQLRestriction(is_visible) 동등 보존
    }

    @Test void noDuplicates() {
        assertThat(cardRepository.searchByCardNameOrProductName("어비스"))
                .extracting(Card::getCardId).doesNotHaveDuplicates();
    }

    @Test void serviceDtoConversion_setSearch() {
        var resp = cardService.searchCards("어비스아이");
        assertThat(resp.getData()).extracting("name").contains("피카츄", "리자몽");
    }

    @Test void emptyName_rejected() {
        assertThat(cardService.searchCards("").getData()).isNull(); // 빈 검색어 거부(기존 정책 유지)
    }

    // ── #5 보완: /cards/market (getMarketCards) 세트명 검색 (거래/시세 검색이 쓰는 경로) ──
    private static final java.util.List<String> RAR = java.util.List.of("AR", "SR");

    @Test void market_setName_returnsSetCards_koVisibleHighRarity() {
        var r = cardRepository.findByRarityOrderByLatestPriceDesc(RAR, "어비스아이", 50, 0);
        assertThat(r).extracting(Card::getCardId).containsExactlyInAnyOrder("a1", "a2"); // KO·AR·visible (EN a3·숨김 a4 제외)
    }

    @Test void market_abyss_bothSets() {
        assertThat(cardRepository.findByRarityOrderByLatestPriceDesc(RAR, "어비스", 50, 0))
                .extracting(Card::getCardId).contains("a1", "a2", "l1");
    }

    @Test void market_cardName_darkrai_preserved() {
        assertThat(cardRepository.findByRarityOrderByLatestPriceDesc(RAR, "다크라이", 50, 0))
                .extracting(Card::getCardId).containsExactly("o1");
    }

    @Test void market_count_matchesData_totalPagesIntegrity() {
        assertThat(cardRepository.countByRarityAndName(RAR, "어비스아이")).isEqualTo(2);
        assertThat(cardRepository.countByRarityAndName(RAR, "어비스")).isEqualTo(3);
    }

    @Test void market_browse_nameEmpty_unaffected() {
        var r = cardRepository.findByRarityOrderByLatestPriceDesc(RAR, "", 50, 0);
        assertThat(r).extracting(Card::getCardId).containsExactlyInAnyOrder("a1", "a2", "l1", "o1", "i1", "i2", "p1"); // KO·AR·visible 전부
        assertThat(cardRepository.countByRarityAndName(RAR, "")).isEqualTo(7);
    }

    @Test void market_allSortBy_setNameWorks() {
        for (var rows : java.util.List.of(
                cardRepository.findByRarityOrderByLatestPriceAsc(RAR, "어비스아이", 50, 0),
                cardRepository.findByRarityOrderByRarityDesc(RAR, "어비스아이", 50, 0),
                cardRepository.findByRarityOrderByLatestDateDesc(RAR, "어비스아이", 50, 0),
                cardRepository.findByRarityOrderByNameAsc(RAR, "어비스아이", 50, 0))) {
            assertThat(rows).extracting(Card::getCardId).containsExactlyInAnyOrder("a1", "a2");
        }
    }

    // ── #5 정규화(canonicalize): 공백·구분자 무시 + 흔한 오타 별칭(전역 fuzzy 아님) ──
    @Test void canonicalize_delimitersAndAlias() {
        assertThat(CardSearchTerms.canonicalize("어비스 아이")).isEqualTo("어비스아이");
        assertThat(CardSearchTerms.canonicalize("인페르노 X")).isEqualTo("인페르노x");
        assertThat(CardSearchTerms.canonicalize("인페리노 X")).isEqualTo("인페르노x"); // 별칭
        assertThat(CardSearchTerms.canonicalize("포켓몬 카드 151")).isEqualTo("포켓몬카드151");
        assertThat(CardSearchTerms.canonicalize("다크라이")).isEqualTo("다크라이");
        assertThat(CardSearchTerms.canonicalize("  ")).isEmpty();
        assertThat(CardSearchTerms.canonicalize(null)).isEmpty();
    }

    @Test void search_spaceVariants_sameAsExact() {
        assertThat(cardService.searchCards("어비스 아이").getData()).extracting("name")
                .containsExactlyInAnyOrder("피카츄", "리자몽", "Pikachu"); // == 어비스아이
        assertThat(cardService.searchCards("포켓몬카드151").getData()).extracting("name").containsExactly("뮤");
        assertThat(cardService.searchCards("151").getData()).extracting("name").containsExactly("뮤");
        assertThat(cardService.searchCards("로스트 어비스").getData()).extracting("name").contains("뮤츠");
    }

    @Test void search_inferno_spaceAndTypoAlias() {
        for (String term : java.util.List.of("인페르노", "인페르노 X", "인페르노X", "인페리노", "인페리노 X")) {
            assertThat(cardService.searchCards(term).getData()).extracting("name")
                    .as("검색어=%s", term).containsExactlyInAnyOrder("라우드본", "윈디");
        }
    }

    @Test void market_spaceAndAlias_viaService() {
        // /cards/market 도 동일 canonicalize — 인페리노 오타·인페르노 X 공백 모두 i1,i2(고레어 2)
        for (String term : java.util.List.of("인페리노", "인페르노 X")) {
            var r = cardService.getMarketCards(RAR, term, 0, 50, "price", "desc");
            assertThat(((Number) r.get("totalElements")).intValue()).as("market=%s", term).isEqualTo(2);
        }
    }

    @Test void cardName_normalizedToo() {
        // 카드명도 정규화: '메가 다크라이' 공백 입력도 '메가다크라이' 카드명에 매칭
        assertThat(cardService.searchCards("메가 다크라이").getData()).extracting("name").contains("메가다크라이");
    }
}
