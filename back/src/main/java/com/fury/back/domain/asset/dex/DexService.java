package com.fury.back.domain.asset.dex;

import com.fury.back.domain.card.Card;
import com.fury.back.storage.CardCdnUrls;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.sql.Timestamp;
import java.util.*;

/**
 * 2026-05-29 Phase B — 도감 service.
 *
 * <p>Codex 사전 검토 Q2/Q3 — hero card = 단일 native query + window function + CASE WHEN rarity priority.
 * <p>박스 이미지 보류 (권리 risk), hero card 이미지로 cover fallback.
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class DexService {

    @PersistenceContext
    private EntityManager em;

    private final CardCdnUrls cardCdnUrls;

    /** 사용자 명시 priority. PR(프로모) 후순위. 알려지지 않은 rarity = 50 (중간). */
    private static final String RARITY_PRIORITY_SQL = """
        CASE c.rarity_code
          WHEN 'MUR' THEN 1
          WHEN 'BWR' THEN 2
          WHEN 'SAR' THEN 3
          WHEN 'SSR' THEN 4
          WHEN 'UR'  THEN 5
          WHEN 'HR'  THEN 6
          WHEN 'CSR' THEN 7
          WHEN 'SR'  THEN 8
          WHEN 'AR'  THEN 9
          WHEN 'ACE' THEN 10
          WHEN 'RRR' THEN 11
          WHEN 'RR'  THEN 12
          WHEN 'H'   THEN 13
          WHEN 'R'   THEN 14
          WHEN 'U'   THEN 15
          WHEN 'C'   THEN 16
          WHEN 'S'   THEN 17
          WHEN 'K'   THEN 18
          WHEN 'PR'  THEN 99
          ELSE 50
        END
        """;

    /**
     * 2026-05-29 Codex MVP — "최신 세대 우선" 정렬. 정확한 "최근 발매" 아님 (release_date 없음).
     * 향후 products.release_date 컬럼 추가 시 이 정렬 deprecated, ORDER BY 한 줄만 교체.
     *
     * 2026-05-29 hotfix — PostgreSQL "could not determine data type of parameter $5"
     * (SQLState 42P18) — inline LIKE 패턴 ('%스칼렛&바이올렛%' 의 `&` 등) 이 Hibernate
     * native query 에서 prepared statement placeholder 로 잘못 변환되는 문제.
     * 해결: 모든 LIKE 패턴을 named param 으로 외부화 (binding 명확).
     * 메모리 feedback_hibernate_native_param_types 참조 — admin chart 와 동일 패턴.
     */
    private static final String PRODUCT_GENERATION_SQL = """
        CASE
          WHEN p.name LIKE CAST(:genMega AS TEXT) THEN 1
          WHEN p.name LIKE CAST(:genSv   AS TEXT) THEN 2
          WHEN p.name LIKE CAST(:genSwsh AS TEXT) THEN 3
          WHEN p.name LIKE CAST(:genSm   AS TEXT) THEN 4
          WHEN p.name LIKE CAST(:genXy   AS TEXT) THEN 5
          WHEN p.name LIKE CAST(:genBw   AS TEXT) THEN 6
          WHEN p.name LIKE CAST(:genDp   AS TEXT) THEN 7
          ELSE 99
        END
        """;

    private static final String GEN_MEGA = "MEGA%";
    private static final String GEN_SV   = "%스칼렛&바이올렛%";
    private static final String GEN_SWSH = "%소드&실드%";
    private static final String GEN_SM   = "%썬&문%";
    private static final String GEN_XY   = "XY%";
    private static final String GEN_BW   = "BW%";
    private static final String GEN_DP   = "DP%";
    private static final String EX_PROMO = "%프로모%";
    private static final String EX_TRAINER_BOX = "%트레이너 박스%";

    // ──────────────────────────────────────────────────────────────────
    // GET /api/assets/dex
    // 한 번의 SQL 로 product 별 hero card + 시리즈 visible 카드 카운트.
    // 사용자 보유 종 수는 별도 lookup (assets join) — index 활용.
    // ──────────────────────────────────────────────────────────────────

    public DexDto.DexMain getDexMain(String userId, int limit) {
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "USER_REQUIRED");
        }

        // 0. 전체 도감 표시 대상 product 수 — totalProducts + hasMore 계산용.
        //   2026-05-29 사용자 명시 필터 (도감 의미 보호):
        //     - ko_visible >= 5  (1~4장짜리 부속/프로모 묶음 제거)
        //     - name NOT LIKE '%프로모%'        (코리안리그 프로모, 프로모 카드 팩 등)
        //     - name NOT LIKE '%트레이너 박스%' (프리미엄 트레이너 박스 등)
        //   메인 query 와 같은 필터 적용 → hasMore 정합성 보장.
        long totalAll = ((Number) em.createNativeQuery(
            "SELECT COUNT(*) FROM (" +
            "  SELECT c.product_id FROM cards c " +
            "  WHERE c.is_visible = TRUE AND c.language = 'KO' " +
            "  GROUP BY c.product_id " +
            "  HAVING COUNT(*) >= 5" +
            ") sub " +
            "JOIN products p ON p.product_id = sub.product_id " +
            "WHERE p.name NOT LIKE CAST(:exPromo AS TEXT) " +
            "  AND p.name NOT LIKE CAST(:exTrainerBox AS TEXT)"
        )
        .setParameter("exPromo", EX_PROMO)
        .setParameter("exTrainerBox", EX_TRAINER_BOX)
        .getSingleResult()).longValue();

        // 1. 각 product 별 hero card (rarity priority + collection_number asc) + visible 카드 카운트 + 최신 카드 시각.
        //    Card @SQLRestriction("is_visible=true") 는 JPQL 만 적용. native query 는 직접 WHERE 필요.
        //    2026-05-29 Codex MVP — generation priority + limit 적용.
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery("""
            WITH visible AS (
              SELECT c.product_id, c.card_id, c.name, c.rarity_code, c.collection_number,
                     c.en_scrydex_ref, c.jp_scrydex_ref, c.created_at,
                     """ + RARITY_PRIORITY_SQL + """
                     AS rarity_priority
              FROM cards c
              WHERE c.is_visible = TRUE AND c.language = 'KO'
            ),
            counted AS (
              SELECT product_id,
                     COUNT(*) AS total_ko_visible,
                     MAX(created_at) AS latest_card_at
              FROM visible
              GROUP BY product_id
              HAVING COUNT(*) >= 5
            ),
            heroed AS (
              SELECT v.*,
                     ROW_NUMBER() OVER (
                       PARTITION BY product_id
                       ORDER BY rarity_priority ASC, collection_number ASC NULLS LAST, card_id ASC
                     ) AS rn
              FROM visible v
            )
            SELECT p.product_id, p.name AS product_name,
                   c.total_ko_visible, c.latest_card_at,
                   h.card_id, h.name AS hero_name, h.rarity_code,
                   h.en_scrydex_ref, h.jp_scrydex_ref
            FROM products p
            JOIN counted c ON c.product_id = p.product_id
            LEFT JOIN heroed h ON h.product_id = p.product_id AND h.rn = 1
            WHERE p.name NOT LIKE CAST(:exPromo AS TEXT)
              AND p.name NOT LIKE CAST(:exTrainerBox AS TEXT)
            ORDER BY
              """ + PRODUCT_GENERATION_SQL + """
              ASC,
              c.latest_card_at DESC NULLS LAST
            LIMIT :limit
            """)
            .setParameter("genMega", GEN_MEGA)
            .setParameter("genSv",   GEN_SV)
            .setParameter("genSwsh", GEN_SWSH)
            .setParameter("genSm",   GEN_SM)
            .setParameter("genXy",   GEN_XY)
            .setParameter("genBw",   GEN_BW)
            .setParameter("genDp",   GEN_DP)
            .setParameter("exPromo", EX_PROMO)
            .setParameter("exTrainerBox", EX_TRAINER_BOX)
            .setParameter("limit",   limit)
            .getResultList();

        // 2. 사용자 보유 종 수 (per product). assets join — distinct card_id 기준.
        @SuppressWarnings("unchecked")
        List<Object[]> ownedRows = em.createNativeQuery("""
            SELECT c.product_id, COUNT(DISTINCT a.card_id) AS owned
            FROM assets a
            JOIN cards c ON c.card_id = a.card_id
            WHERE a.user_id = :uid AND c.is_visible = TRUE AND c.language = 'KO'
            GROUP BY c.product_id
            """).setParameter("uid", userId).getResultList();
        Map<String, Integer> ownedByProduct = new HashMap<>();
        for (Object[] r : ownedRows) {
            ownedByProduct.put((String) r[0], ((Number) r[1]).intValue());
        }

        // 3. BoxItem 조립 + 통계.
        List<DexDto.BoxItem> items = new ArrayList<>(rows.size());
        int totalOwned = 0, totalAvail = 0, ownedSeries = 0;
        for (Object[] r : rows) {
            String productId = (String) r[0];
            String productName = (String) r[1];
            int totalKo = ((Number) r[2]).intValue();
            Timestamp latestCardAt = (Timestamp) r[3];
            String heroId = (String) r[4];
            String heroName = (String) r[5];
            String heroRarity = (String) r[6];
            String enRef = (String) r[7];
            String jpRef = (String) r[8];

            int owned = ownedByProduct.getOrDefault(productId, 0);
            totalOwned += owned;
            totalAvail += totalKo;
            if (owned > 0) ownedSeries++;

            // hero 카드 이미지 URL — Card stub 만들고 CardCdnUrls 재사용.
            String heroImageUrl = null;
            if (heroId != null) {
                Card stub = Card.builder()
                        .cardId(heroId)
                        .enScrydexRef(enRef)
                        .jpScrydexRef(jpRef)
                        .build();
                heroImageUrl = cardCdnUrls.forCard(stub);
            }

            items.add(DexDto.BoxItem.builder()
                    .productId(productId)
                    .productName(productName)
                    .totalKoVisible(totalKo)
                    .ownedCount(owned)
                    .heroCardId(heroId)
                    .heroCardName(heroName)
                    .heroCardRarity(heroRarity)
                    .heroCardImageUrl(heroImageUrl)
                    .latestCardAt(latestCardAt != null ? latestCardAt.toLocalDateTime().toString() : null)
                    .build());
        }

        return DexDto.DexMain.builder()
                .products(items)
                .totalProducts((int) totalAll)            // 전체 KO visible product (Codex Q3)
                .hasMore(items.size() < totalAll)
                .ownedSeriesCount(ownedSeries)            // 응답 N개 중 보유 시리즈
                .totalOwnedCards(totalOwned)              // 응답 N개 합산
                .totalAvailableCards(totalAvail)          // 응답 N개 합산
                .build();
    }

    // ──────────────────────────────────────────────────────────────────
    // GET /api/assets/dex/{productId}
    // ──────────────────────────────────────────────────────────────────

    public DexDto.DexDetail getDexDetail(String userId, String productId) {
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "USER_REQUIRED");
        }

        @SuppressWarnings("unchecked")
        List<Object> nameRows = em.createNativeQuery(
                "SELECT name FROM products WHERE product_id = :pid")
                .setParameter("pid", productId)
                .getResultList();
        if (nameRows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "PRODUCT_NOT_FOUND");
        }
        String productName = (String) nameRows.get(0);

        // 시리즈 visible 카드 전체 (collection_number asc).
        @SuppressWarnings("unchecked")
        List<Object[]> cardRows = em.createNativeQuery("""
            SELECT c.card_id, c.name, c.rarity_code, c.collection_number,
                   c.en_scrydex_ref, c.jp_scrydex_ref,
                   """ + RARITY_PRIORITY_SQL + """
                   AS rarity_priority
            FROM cards c
            WHERE c.product_id = :pid AND c.is_visible = TRUE AND c.language = 'KO'
            ORDER BY c.collection_number ASC NULLS LAST, c.card_id ASC
            """).setParameter("pid", productId).getResultList();

        // 사용자 보유 — card_id → quantity 합산.
        @SuppressWarnings("unchecked")
        List<Object[]> ownedRows = em.createNativeQuery("""
            SELECT a.card_id, SUM(a.quantity) AS qty
            FROM assets a
            JOIN cards c ON c.card_id = a.card_id
            WHERE a.user_id = :uid AND c.product_id = :pid AND c.is_visible = TRUE AND c.language = 'KO'
            GROUP BY a.card_id
            """).setParameter("uid", userId).setParameter("pid", productId).getResultList();
        Map<String, Integer> ownedQty = new HashMap<>();
        for (Object[] r : ownedRows) {
            ownedQty.put((String) r[0], ((Number) r[1]).intValue());
        }

        // 카드 list 조립.
        List<DexDto.DexCard> allCards = new ArrayList<>(cardRows.size());
        // hits 후보용 (rarity priority 정렬 후 top 4).
        List<Object[]> hitsCand = new ArrayList<>(cardRows);
        hitsCand.sort(Comparator.comparingInt(r -> ((Number) r[6]).intValue()));

        for (Object[] r : cardRows) {
            String cardId = (String) r[0];
            String name = (String) r[1];
            String rarity = (String) r[2];
            String colNum = (String) r[3];
            String enRef = (String) r[4];
            String jpRef = (String) r[5];

            int qty = ownedQty.getOrDefault(cardId, 0);
            Card stub = Card.builder()
                    .cardId(cardId).enScrydexRef(enRef).jpScrydexRef(jpRef).build();
            allCards.add(DexDto.DexCard.builder()
                    .cardId(cardId)
                    .name(name)
                    .rarityCode(rarity)
                    .collectionNumber(colNum)
                    .imageUrl(cardCdnUrls.forCard(stub))
                    .owned(qty > 0)
                    .quantity(qty)
                    .build());
        }

        List<DexDto.DexCard> hits = new ArrayList<>(4);
        for (Object[] r : hitsCand) {
            if (hits.size() >= 4) break;
            String cardId = (String) r[0];
            String name = (String) r[1];
            String rarity = (String) r[2];
            String colNum = (String) r[3];
            String enRef = (String) r[4];
            String jpRef = (String) r[5];
            int qty = ownedQty.getOrDefault(cardId, 0);
            Card stub = Card.builder()
                    .cardId(cardId).enScrydexRef(enRef).jpScrydexRef(jpRef).build();
            hits.add(DexDto.DexCard.builder()
                    .cardId(cardId)
                    .name(name)
                    .rarityCode(rarity)
                    .collectionNumber(colNum)
                    .imageUrl(cardCdnUrls.forCard(stub))
                    .owned(qty > 0)
                    .quantity(qty)
                    .build());
        }

        int totalKo = cardRows.size();
        int owned = ownedQty.size();

        return DexDto.DexDetail.builder()
                .productId(productId)
                .productName(productName)
                .totalKoVisible(totalKo)
                .ownedCount(owned)
                .hits(hits)
                .cards(allCards)
                .build();
    }
}
