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

    // 2026-05-29 hotfix 3 — PRODUCT_GENERATION_SQL (CASE WHEN LIKE) 제거.
    // 한국어 + & 포함 LIKE 패턴이 Hibernate 6 native query 에서 prepared statement
    // 타입 추론 실패 (42P18) 재발. named param 외부화 + CAST AS TEXT 둘 다 안 됨.
    // → generationPriority(String name) Java 메서드 로 이전 (parsing 부담 무시 가능).


    /** 2026-05-29 hotfix 3 — Java side prefix priority (SQL LIKE 우회).
     *  prefix 매칭 — DB 실측:
     *    MEGA*               → 1
     *    *스칼렛&바이올렛*    → 2  (포켓몬 카드 게임 ~, 강화/하이클래스/확장팩 포함)
     *    *소드&실드*          → 3
     *    *썬&문*              → 4
     *    XY*                 → 5  (XY BREAK 도 포함)
     *    BW*                 → 6
     *    DP*                 → 7
     *    기타                → 99
     */
    private static int generationPriority(String name) {
        if (name == null) return 99;
        if (name.startsWith("MEGA"))           return 1;
        if (name.contains("스칼렛&바이올렛")) return 2;
        if (name.contains("소드&실드"))        return 3;
        if (name.contains("썬&문"))            return 4;
        if (name.startsWith("XY"))             return 5;
        if (name.startsWith("BW"))             return 6;
        if (name.startsWith("DP"))             return 7;
        return 99;
    }

    // ──────────────────────────────────────────────────────────────────
    // GET /api/assets/dex
    // 한 번의 SQL 로 product 별 hero card + 시리즈 visible 카드 카운트.
    // 사용자 보유 종 수는 별도 lookup (assets join) — index 활용.
    // ──────────────────────────────────────────────────────────────────

    public DexDto.DexMain getDexMain(String userId, int limit) {
        if (userId == null || userId.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "USER_REQUIRED");
        }

        // 2026-05-29 hotfix 3 — SQL LIKE/NOT LIKE 모두 제거, 정렬/필터 Java side 로 이전.
        //   원인: Hibernate native query 가 '%소드&실드%' 같은 한국어+& 포함 LIKE 패턴을
        //         PostgreSQL prepared statement 로 binding 시 타입 추론 실패 (SQLState 42P18).
        //         named param 외부화 + CAST AS TEXT 명시해도 동일 에러 — Hibernate 6 native
        //         query 에서 CASE WHEN LIKE 안 named param 처리 가능한 버그 추정.
        //   해결: SQL 은 단순 SELECT + count + ORDER BY latest_card_at + 모든 product 반환.
        //         Java 측에서 prefix priority 정렬 + name contains filter + sublist.
        //         124개 in-memory 처리 → 부하 무시 가능.

        // 1. 모든 product (KO visible >= 5) — Java 측에서 정렬/필터.
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
            ORDER BY c.latest_card_at DESC NULLS LAST
            """).getResultList();

        // 2. Java side filter — name contains 프로모 / 트레이너 박스 제거.
        rows = rows.stream()
                .filter(r -> {
                    String name = (String) r[1];
                    if (name == null) return false;
                    if (name.contains("프로모")) return false;
                    if (name.contains("트레이너 박스")) return false;
                    return true;
                })
                .toList();

        long totalAll = rows.size();

        // 3. Java side sort — generation priority ASC, latest_card_at DESC (이미 SQL 정렬됨 유지).
        rows = rows.stream()
                .sorted((a, b) -> {
                    int ga = generationPriority((String) a[1]);
                    int gb = generationPriority((String) b[1]);
                    return Integer.compare(ga, gb);  // stable sort → latest_card_at DESC 유지
                })
                .toList();

        // 4. limit 적용.
        if (rows.size() > limit) {
            rows = rows.subList(0, limit);
        }

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
            // 2026-05-29 hotfix 3 (Codex Q2): JDBC driver 가 timestamp 컬럼을 LocalDateTime
            // 또는 java.sql.Timestamp 로 반환 — driver 버전에 따라 다름. 두 케이스 모두 처리.
            String latestCardAt = r[3] == null ? null :
                (r[3] instanceof Timestamp ts ? ts.toLocalDateTime().toString() : r[3].toString());
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
                    .latestCardAt(latestCardAt)
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
        List<Object[]> productRows = em.createNativeQuery(
                "SELECT name, dex_hit_card_ids FROM products WHERE product_id = :pid")
                .setParameter("pid", productId)
                .getResultList();
        if (productRows.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "PRODUCT_NOT_FOUND");
        }
        String productName = (String) productRows.get(0)[0];
        String dexHitCsv = (String) productRows.get(0)[1];

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

        // 카드 list 조립 + cardId → DexCard map (override resolve 재사용).
        List<DexDto.DexCard> allCards = new ArrayList<>(cardRows.size());
        Map<String, DexDto.DexCard> byId = new HashMap<>(cardRows.size());
        // hits 자동 후보 (rarity priority 정렬 후 top 4) — override null/empty 시 fallback.
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
            DexDto.DexCard dc = DexDto.DexCard.builder()
                    .cardId(cardId)
                    .name(name)
                    .rarityCode(rarity)
                    .collectionNumber(colNum)
                    .imageUrl(cardCdnUrls.forCard(stub))
                    .owned(qty > 0)
                    .quantity(qty)
                    .build();
            allCards.add(dc);
            byId.put(cardId, dc);
        }

        // 2026-05-30 Cycle 2 — products.dex_hit_card_ids override 우선, 없거나 모두 invalid 시 기존 자동 fallback.
        // CSV 형식: "CRD_xxx,CRD_yyy,...". 순서 = display 순서. cap 6 (컬렉션형 VSTAR/테라스탈/151/VMAX 허용).
        // cardRows 가 product_id + is_visible + language='KO' 필터링 → byId 재사용 시 inherit (별 query 불필요).
        List<DexDto.DexCard> hits = new ArrayList<>(6);
        if (dexHitCsv != null && !dexHitCsv.isBlank()) {
            String[] tokens = dexHitCsv.split(",");
            Set<String> seen = new HashSet<>();
            for (String t : tokens) {
                if (hits.size() >= 6) break;
                String id = t.trim();
                if (id.isEmpty() || !seen.add(id)) continue;
                DexDto.DexCard dc = byId.get(id);
                if (dc != null) hits.add(dc);
            }
        }
        // valid resolve 0건 시 자동 fallback (Codex GO 조건 — empty row 방지).
        if (hits.isEmpty()) {
            for (Object[] r : hitsCand) {
                if (hits.size() >= 4) break;
                hits.add(byId.get((String) r[0]));
            }
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
