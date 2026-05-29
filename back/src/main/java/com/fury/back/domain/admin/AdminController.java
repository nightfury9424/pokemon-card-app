package com.fury.back.domain.admin;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.RawPsa10Ratio;
import com.fury.back.domain.price.RawPsa10RatioCalculator;
import com.fury.back.domain.price.RawPsa10RatioRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import lombok.RequiredArgsConstructor;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.web.bind.annotation.*;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

import java.net.http.HttpClient;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.concurrent.Executors;
import java.util.concurrent.ExecutorService;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    @PersistenceContext
    private EntityManager em;

    private final RawPsa10RatioCalculator rawPsa10RatioCalculator;
    private final RawPsa10RatioRepository rawPsa10RatioRepository;

    /** 2026-05-29 P-1: 스캐너 stats proxy. brower → backend → scanner (docker network). */
    @Value("${scanner.base-url:http://localhost:8082}")
    private String scannerBaseUrl;

    /** RestClient with short timeout — scanner 다운 시 dashboard 응답 지연 막기. */
    private RestClient scannerClient;

    /** 2026-05-29 P0 #2 — 서비스 상태 정책 토글. enabled=false 면 reachable 여부 무관하게 Disabled. */
    @Value("${app.services.scanner.enabled:false}")
    private boolean scannerEnabled;
    @Value("${app.services.grading.enabled:false}")
    private boolean gradingEnabled;
    @Value("${grading.service.url:}")
    private String gradingBaseUrl;

    /**
     * 2026-05-29 Codex 사후 Q2 — bounded executor + RestClient timeout.
     *  - ForkJoin common pool 포화 방지 (동시 admin 다수가 dashboard 새로고침 시 worker thread 점거).
     *  - HttpClient 1.5s connect/request timeout — slow scanner 가 backend thread 잡아두는 거 차단.
     *  전체 timeout = joinSafe 2s upper bound, 평소엔 1.5s 안에 끝남.
     */
    private static final ExecutorService SERVICE_PROBE_POOL =
            Executors.newFixedThreadPool(4, r -> {
                Thread t = new Thread(r, "svc-probe");
                t.setDaemon(true);
                return t;
            });

    private static final JdkClientHttpRequestFactory PROBE_REQUEST_FACTORY = buildProbeRequestFactory();

    private static JdkClientHttpRequestFactory buildProbeRequestFactory() {
        HttpClient httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofMillis(1500))
                .build();
        JdkClientHttpRequestFactory f = new JdkClientHttpRequestFactory(httpClient);
        f.setReadTimeout(Duration.ofMillis(1500));
        return f;
    }

    /* ── 공통 헬퍼 ── */
    private long count(String jpql) {
        return ((Number) em.createQuery(jpql).getSingleResult()).longValue();
    }

    /* ════════════════════════════════
       헬스체크
       ════════════════════════════════ */
    @GetMapping("/health")
    public ReturnData<?> health() {
        return ReturnData.success(Map.of("status", "ok"));
    }

    /* ════════════════════════════════
       스탯 카드
       ════════════════════════════════ */
    @GetMapping("/stats/users")
    public ReturnData<?> statsUsers() {
        long total = count("SELECT COUNT(u) FROM User u");
        long today = ((Number) em.createQuery(
            "SELECT COUNT(u) FROM User u WHERE u.createdAt >= :start"
        ).setParameter("start", LocalDate.now().atStartOfDay()).getSingleResult()).longValue();

        // 7일 전 대비 신규 증감
        long lastWeek = ((Number) em.createQuery(
            "SELECT COUNT(u) FROM User u WHERE u.createdAt >= :start AND u.createdAt < :end"
        ).setParameter("start", LocalDate.now().minusDays(14).atStartOfDay())
         .setParameter("end",   LocalDate.now().minusDays(7).atStartOfDay())
         .getSingleResult()).longValue();
        long thisWeek = ((Number) em.createQuery(
            "SELECT COUNT(u) FROM User u WHERE u.createdAt >= :start"
        ).setParameter("start", LocalDate.now().minusDays(7).atStartOfDay())
         .getSingleResult()).longValue();
        Integer delta = lastWeek == 0 ? null : (int) Math.round((thisWeek - lastWeek) * 100.0 / lastWeek);

        return ReturnData.success(Map.of("total", total, "today", today, "weeklyDelta", delta == null ? 0 : delta));
    }

    @GetMapping("/stats/cards")
    public ReturnData<?> statsCards() {
        // 2026-05-29 P-1: JPQL은 Card @SQLRestriction("is_visible=true") 자동 적용 → 가시 카드만.
        // 사용자가 봤던 "3,425"는 KO 가시 카드 카운트가 맞음. 운영자에게 가려진 row도 알려주자.
        // hidden = native count (visible+hidden) − visible.
        long visibleKo = count("SELECT COUNT(c) FROM Card c WHERE c.language = 'KO'");
        long totalKoNative = ((Number) em.createNativeQuery(
            "SELECT COUNT(*) FROM cards WHERE language = 'KO'"
        ).getSingleResult()).longValue();
        long hiddenKo = Math.max(0, totalKoNative - visibleKo);
        return ReturnData.success(Map.of(
            "total",  visibleKo,
            "hidden", hiddenKo
        ));
    }

    @GetMapping("/stats/trades")
    public ReturnData<?> statsTrades() {
        long active = count("SELECT COUNT(t) FROM TradePost t WHERE t.status = 'OPEN'");
        long total  = count("SELECT COUNT(t) FROM TradePost t");
        return ReturnData.success(Map.of("active", active, "total", total));
    }

    @GetMapping("/stats/scans")
    public ReturnData<?> statsScans() {
        // scan_logs 테이블 없음 — 추후 연동. P-1: 분모 0 가드는 프론트에서 처리.
        return ReturnData.success(Map.of("total", 0, "today", 0, "weeklyDelta", 0));
    }

    /* ════════════════════════════════
       2026-05-29 P-1: 운영 현황 (사이드바 박스 교체)
       — 사이드바 하드코딩 "서비스 정상 운영 중" 문구 대신 실제 cron 실행 시각.
       price_snapshots 최대 traded_at + admin_actions 최대 created_at 한 번에 반환.
       ════════════════════════════════ */
    @GetMapping("/ops-status")
    public ReturnData<?> opsStatus() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("lastKoBatch",  maxTradedAt("KO_ESTIMATED"));
        // SCRYDEX_EN + SCRYDEX_JP 합산 최대 — native query 의 IN(:list) parameter expansion 은
        // Hibernate 6 도 driver-dependent (Codex 리뷰 Q3). 리터럴 IN 으로 binding 우회.
        result.put("lastScrydex",  toIso(safeMax(
            "SELECT MAX(traded_at) FROM price_snapshots WHERE source IN ('SCRYDEX_EN', 'SCRYDEX_JP')")));
        result.put("lastKream",    maxTradedAt("KREAM"));
        result.put("lastNaver",    maxTradedAt("NAVER_CAFE"));
        // admin_actions 테이블 — 마지막 운영 액션 시각 (관리자가 마지막으로 뭔가 했는지 확인용).
        try {
            result.put("lastAdminAction", toIso(em.createNativeQuery(
                "SELECT MAX(created_at) FROM admin_actions"
            ).getSingleResult()));
        } catch (Exception e) {
            result.put("lastAdminAction", null);
        }
        return ReturnData.success(result);
    }

    /** native query 가 java.sql.Timestamp 를 돌려주는데 Jackson 기본 직렬화는 epoch millis 라
        프론트 new Date() 파싱이 안 됨 → ISO-8601 string 으로 변환.
        instanceof pattern (Java 16+) 사용 — Timestamp 아니면 .toString() fallback (LocalDateTime/Instant 도 ISO 형식).
        Codex 리뷰 Q2: 직접 cast 아니므로 ClassCastException 없음. */
    private String toIso(Object raw) {
        if (raw == null) return null;
        if (raw instanceof Timestamp ts) return ts.toLocalDateTime().toString();
        return raw.toString();
    }

    private Object safeMax(String literalSql) {
        try { return em.createNativeQuery(literalSql).getSingleResult(); }
        catch (Exception e) { return null; }
    }

    private String maxTradedAt(String source) {
        try {
            return toIso(em.createNativeQuery(
                "SELECT MAX(traded_at) FROM price_snapshots WHERE source = :s"
            ).setParameter("s", source).getSingleResult());
        } catch (Exception e) {
            return null;
        }
    }

    /* ════════════════════════════════
       2026-05-29 P0 #2: 서비스 상태 (병렬 health check + 분류)
       — 브라우저에서 직접 localhost:8082 호출하던 ServiceRow 대체.
       Codex 사전 Q2: enabled=false 무조건 Disabled, /health 3개 병렬, 전체 timeout ≤2s.
       상태:
         RUNNING        = enabled=true + URL 설정됨 + /health 200 within 1.5s
         DOWN           = enabled=true + URL 설정됨 + 응답 실패/timeout
         DISABLED       = enabled=false (URL 도달성 무관)
         NOT_CONFIGURED = URL 비어있음
       ════════════════════════════════ */
    @GetMapping("/services-status")
    public ReturnData<?> servicesStatus() {
        long t0 = System.currentTimeMillis();

        // 병렬 health check — bounded executor (Codex 사후 Q2). backend 자체는 즉시 RUNNING.
        java.util.concurrent.CompletableFuture<Map<String, Object>> backFuture =
                java.util.concurrent.CompletableFuture.completedFuture(
                        Map.of("name", "Spring Boot API", "status", "RUNNING",
                               "responseMs", 0, "url", "self"));
        java.util.concurrent.CompletableFuture<Map<String, Object>> scannerFuture =
                java.util.concurrent.CompletableFuture.supplyAsync(
                        () -> probeService("FastAPI Scanner", scannerBaseUrl, scannerEnabled),
                        SERVICE_PROBE_POOL);
        java.util.concurrent.CompletableFuture<Map<String, Object>> gradingFuture =
                java.util.concurrent.CompletableFuture.supplyAsync(
                        () -> probeService("FastAPI Grading", gradingBaseUrl, gradingEnabled),
                        SERVICE_PROBE_POOL);

        // 전체 2초 timeout — slow service 가 dashboard 전체 잡지 못하게.
        List<Map<String, Object>> services = new ArrayList<>();
        services.add(joinSafe(backFuture));
        services.add(joinSafe(scannerFuture));
        services.add(joinSafe(gradingFuture));

        return ReturnData.success(Map.of(
            "services", services,
            "totalMs",  System.currentTimeMillis() - t0
        ));
    }

    private Map<String, Object> joinSafe(java.util.concurrent.CompletableFuture<Map<String, Object>> f) {
        try {
            return f.get(2, java.util.concurrent.TimeUnit.SECONDS);
        } catch (Exception e) {
            return Map.of("name", "unknown", "status", "DOWN", "error", e.getClass().getSimpleName());
        }
    }

    /** 단일 서비스 분류. URL 비어있으면 NOT_CONFIGURED, enabled=false 면 DISABLED. */
    private Map<String, Object> probeService(String name, String baseUrl, boolean enabled) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("name", name);
        result.put("url", baseUrl == null ? "" : baseUrl);

        if (baseUrl == null || baseUrl.isBlank()) {
            result.put("status", "NOT_CONFIGURED");
            return result;
        }
        if (!enabled) {
            result.put("status", "DISABLED");
            return result;
        }
        long t = System.currentTimeMillis();
        try {
            // Codex 사후 Q2: explicit connect/read timeout via shared JdkClientHttpRequestFactory.
            RestClient client = RestClient.builder()
                    .baseUrl(baseUrl)
                    .requestFactory(PROBE_REQUEST_FACTORY)
                    .build();
            String body = client.get().uri("/health").retrieve().body(String.class);
            result.put("status", "RUNNING");
            result.put("responseMs", System.currentTimeMillis() - t);
            if (body != null && body.length() < 200) result.put("body", body);
        } catch (Exception e) {
            result.put("status", "DOWN");
            result.put("error", e.getClass().getSimpleName());
            result.put("responseMs", System.currentTimeMillis() - t);
        }
        return result;
    }

    /* ════════════════════════════════
       2026-05-29 P-1: 스캐너 stats proxy
       — Scanner.jsx 가 브라우저에서 직접 http://localhost:8082/info 호출 → prod 에선 닿지 않음.
       backend 가 docker network 안 scanner:8082/health 를 호출 ({"status":"ok","vectors":N}).
       /info, /rebuild 등 미구현 endpoint 는 connected=false 로 표시.
       ════════════════════════════════ */
    @GetMapping("/scanner/stats")
    public ReturnData<?> scannerStats() {
        if (scannerClient == null) {
            scannerClient = RestClient.builder()
                    .baseUrl(scannerBaseUrl)
                    .build();
        }
        Map<String, Object> result = new LinkedHashMap<>();
        try {
            // /health 가 {"status":"ok","vectors":N} 반환 (prod 확인).
            Map<String, Object> health = scannerClient.get()
                    .uri("/health")
                    .retrieve()
                    .body(new ParameterizedTypeReference<>() {});
            if (health != null) {
                result.put("connected", true);
                result.put("status",      health.get("status"));
                result.put("totalVectors", health.get("vectors"));
                result.put("dim",         1536); // DINOv2 ViT-L/14 고정.
                result.put("baseUrl",     scannerBaseUrl);
            } else {
                result.put("connected", false);
                result.put("error", "empty response");
            }
        } catch (Exception e) {
            result.put("connected", false);
            result.put("error", e.getClass().getSimpleName());
        }
        return ReturnData.success(result);
    }

    /* ════════════════════════════════
       차트 데이터 (최근 7일)
       ════════════════════════════════ */
    /**
     * 2026-05-29 P0 #1 — 누적+신규 한 query (window function) 로 N+1 제거.
     *   - days param: default 30, max 90.
     *   - 누적 = 시작일 이전 baseline + 윈도우 내 running sum.
     *
     * 2026-05-29 hotfix — PostgreSQL `could not determine data type of parameter $5`:
     *   원인: `::date` PostgreSQL-only cast + named param 두 번 등장 시 prepared statement 타입 추론 실패.
     *   수정: 명시 CAST(... AS TIMESTAMP) + TO_CHAR(d.day, 'MM/DD') 로 SQL-side 포매팅
     *        (java.sql.Date vs LocalDate driver-dependent 캐스트도 같이 우회).
     *        try-catch 로 fallback empty list — endpoint 500 안 던짐.
     */
    @GetMapping("/stats/users/chart")
    public ReturnData<?> usersChart(@RequestParam(defaultValue = "30") int days) {
        int safeDays = Math.min(Math.max(days, 7), 90);
        LocalDate start = LocalDate.now().minusDays(safeDays - 1);

        try {
            // 시작일 이전 전체 신규 = "초기 누적".
            long baseline = ((Number) em.createNativeQuery(
                "SELECT COUNT(*) FROM users WHERE created_at < CAST(:start AS TIMESTAMP)"
            ).setParameter("start", start.atStartOfDay()).getSingleResult()).longValue();

            // 명시 CAST + TO_CHAR — Hibernate prepared statement 타입 추론 안정화.
            @SuppressWarnings("unchecked")
            List<Object[]> rows = em.createNativeQuery(
                "WITH d AS ( " +
                "  SELECT generate_series( " +
                "    CAST(:start AS TIMESTAMP)::date, " +
                "    CAST(:endIncl AS TIMESTAMP)::date, " +
                "    '1 day'::interval " +
                "  )::date AS day " +
                "), " +
                "n AS ( " +
                "  SELECT created_at::date AS day, COUNT(*) AS cnt " +
                "  FROM users " +
                "  WHERE created_at >= CAST(:start AS TIMESTAMP) " +
                "    AND created_at <  CAST(:endExclusive AS TIMESTAMP) " +
                "  GROUP BY created_at::date " +
                ") " +
                "SELECT TO_CHAR(d.day, 'MM/DD') AS day_label, " +
                "       COALESCE(n.cnt, 0) AS new_users, " +
                "       SUM(COALESCE(n.cnt, 0)) OVER (ORDER BY d.day) AS cumulative_in_window " +
                "FROM d LEFT JOIN n ON d.day = n.day " +
                "ORDER BY d.day"
            ).setParameter("start",        start.atStartOfDay())
             .setParameter("endIncl",      LocalDate.now().atStartOfDay())
             .setParameter("endExclusive", LocalDate.now().plusDays(1).atStartOfDay())
             .getResultList();

            List<Map<String, Object>> result = new ArrayList<>();
            for (Object[] r : rows) {
                // r[0] = String (TO_CHAR), r[1] = new_users, r[2] = cumulative in window
                String dayLabel = String.valueOf(r[0]);
                long newUsers   = ((Number) r[1]).longValue();
                long cumWindow  = ((Number) r[2]).longValue();
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("day", dayLabel);
                row.put("신규유저", newUsers);
                row.put("누적", baseline + cumWindow);
                result.add(row);
            }
            return ReturnData.success(result);
        } catch (Exception e) {
            // 안전망 — 차트가 비어도 dashboard 자체는 살림.
            return ReturnData.success(new ArrayList<Map<String, Object>>());
        }
    }

    @GetMapping("/stats/scans/chart")
    public ReturnData<?> scansChart() {
        DateTimeFormatter dayFmt = DateTimeFormatter.ofPattern("MM/dd");
        List<Map<String, Object>> result = new ArrayList<>();
        for (int i = 6; i >= 0; i--) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("day",  LocalDate.now().minusDays(i).format(dayFmt));
            row.put("스캔수", 0);
            result.add(row);
        }
        return ReturnData.success(result);
    }

    /* ════════════════════════════════
       유저 목록
       ════════════════════════════════ */
    @GetMapping("/users")
    public ReturnData<?> users(
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "15") int size,
            @RequestParam(required = false)    String search
    ) {
        String where = (search != null && !search.isBlank())
            ? " WHERE u.nickname LIKE :q OR u.email LIKE :q"
            : "";

        var countQ = em.createQuery("SELECT COUNT(u) FROM User u" + where);
        var listQ  = em.createQuery("SELECT u FROM User u" + where + " ORDER BY u.createdAt DESC");

        if (search != null && !search.isBlank()) {
            String q = "%" + search + "%";
            countQ.setParameter("q", q);
            listQ .setParameter("q", q);
        }

        long total = ((Number) countQ.getSingleResult()).longValue();
        @SuppressWarnings("unchecked")
        List<?> rows = listQ.setFirstResult(page * size).setMaxResults(size).getResultList();

        List<Map<String, Object>> content = new ArrayList<>();
        for (Object obj : rows) {
            var u = (com.fury.back.domain.user.User) obj;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id",        u.getUserId());
            m.put("nickname",  u.getNickname());
            m.put("email",     u.getEmail());
            m.put("createdAt", u.getCreatedAt());
            m.put("status",    "ACTIVE");
            m.put("scanCount",  0);
            m.put("tradeCount", 0);
            content.add(m);
        }

        return ReturnData.success(Map.of(
            "content",       content,
            "totalElements", total,
            "totalPages",    (int) Math.ceil((double) total / size),
            "page",          page
        ));
    }

    /* ════════════════════════════════
       카드 목록
       ════════════════════════════════ */
    @GetMapping("/cards")
    public ReturnData<?> cards(
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "15") int size,
            @RequestParam(required = false)    String search,
            @RequestParam(required = false)    String rarity
    ) {
        StringBuilder where = new StringBuilder(" WHERE c.language = 'KO'");
        if (search != null && !search.isBlank()) where.append(" AND c.name LIKE :search");
        if (rarity != null && !rarity.isBlank()) where.append(" AND c.rarityCode = :rarity");

        var countQ = em.createQuery("SELECT COUNT(c) FROM Card c" + where);
        var listQ  = em.createQuery("SELECT c FROM Card c" + where + " ORDER BY c.createdAt DESC");

        if (search != null && !search.isBlank()) {
            countQ.setParameter("search", "%" + search + "%");
            listQ .setParameter("search", "%" + search + "%");
        }
        if (rarity != null && !rarity.isBlank()) {
            countQ.setParameter("rarity", rarity);
            listQ .setParameter("rarity", rarity);
        }

        long total = ((Number) countQ.getSingleResult()).longValue();
        @SuppressWarnings("unchecked")
        List<?> rows = listQ.setFirstResult(page * size).setMaxResults(size).getResultList();

        List<Map<String, Object>> content = new ArrayList<>();
        for (Object obj : rows) {
            var c = (com.fury.back.domain.card.Card) obj;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id",         c.getCardId());
            m.put("nameKo",     c.getName());
            m.put("nameEn",     null);
            m.put("setName",    c.getProductId());
            m.put("rarity",     c.getRarityCode());
            m.put("scanCount",  0);
            m.put("enScrydexRef", c.getEnScrydexRef());
            content.add(m);
        }

        return ReturnData.success(Map.of(
            "content",       content,
            "totalElements", total,
            "totalPages",    (int) Math.ceil((double) total / size),
            "page",          page
        ));
    }

    /* ════════════════════════════════
       세트(Product) 목록 (카드 추가 드롭다운용)
       ════════════════════════════════ */
    @GetMapping("/products")
    public ReturnData<?> products(@RequestParam(required = false) String search) {
        String jpql = "SELECT p FROM Product p" +
                (search != null && !search.isBlank() ? " WHERE p.name LIKE :search" : "") +
                " ORDER BY p.name ASC";
        var q = em.createQuery(jpql);
        if (search != null && !search.isBlank()) q.setParameter("search", "%" + search + "%");
        @SuppressWarnings("unchecked")
        List<?> rows = q.setMaxResults(200).getResultList();
        List<Map<String, Object>> result = new ArrayList<>();
        for (Object obj : rows) {
            var p = (com.fury.back.domain.product.Product) obj;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id",   p.getProductId());
            m.put("name", p.getName());
            result.add(m);
        }
        return ReturnData.success(result);
    }

    /* ════════════════════════════════
       카드 추가 (KO/EN/JP 3가지 타입)
       ════════════════════════════════ */
    @PostMapping("/cards")
    @org.springframework.transaction.annotation.Transactional
    public ReturnData<?> addCard(@RequestBody Map<String, Object> body) {
        String type        = (String) body.get("type");        // KO | EN | JP
        String name        = (String) body.get("name");
        String productId   = (String) body.get("productId");
        String rarityCode  = (String) body.get("rarityCode");
        String colNumber   = (String) body.get("collectionNumber");
        String superType   = (String) body.getOrDefault("superType", "POKEMON").toString();
        String subType     = (String) body.get("subType");
        String cardType    = (String) body.get("cardType");
        String officialCode = (String) body.get("officialCardCode");
        String enRef       = (String) body.get("enScrydexRef");
        String jpRef       = (String) body.get("jpScrydexRef");
        String language    = "KO".equals(type) ? "KO" : "EN".equals(type) ? "EN" : "JP";

        if (name == null || name.isBlank())      return ReturnData.badRequest("name은 필수입니다.");
        if (productId == null || productId.isBlank()) return ReturnData.badRequest("productId는 필수입니다.");
        if (rarityCode == null || rarityCode.isBlank()) return ReturnData.badRequest("rarityCode는 필수입니다.");

        // 중복 체크: officialCardCode
        if (officialCode != null && !officialCode.isBlank()) {
            Long dup = (Long) em.createQuery(
                "SELECT COUNT(c) FROM Card c WHERE c.officialCardCode = :code")
                .setParameter("code", officialCode).getSingleResult();
            if (dup > 0) return ReturnData.badRequest("이미 존재하는 officialCardCode: " + officialCode);
        }

        String cardId = "CRD_" + java.util.UUID.randomUUID().toString().replace("-", "").toUpperCase();
        var now = java.time.LocalDateTime.now();

        em.createNativeQuery("""
            INSERT INTO cards (card_id, product_id, official_card_code, name, collection_number,
              rarity_code, language, super_type, sub_type, card_type,
              en_scrydex_ref, jp_scrydex_ref, is_promo_exclusive, created_at, updated_at)
            VALUES (?,?,?,?,?,?,?,?,?,?,?,?,false,?,?)
            """)
            .setParameter(1,  cardId)
            .setParameter(2,  productId)
            .setParameter(3,  officialCode != null ? officialCode : "")
            .setParameter(4,  name)
            .setParameter(5,  colNumber)
            .setParameter(6,  rarityCode)
            .setParameter(7,  language)
            .setParameter(8,  superType)
            .setParameter(9,  subType)
            .setParameter(10, cardType)
            .setParameter(11, enRef)
            .setParameter(12, jpRef)
            .setParameter(13, now)
            .setParameter(14, now)
            .executeUpdate();

        return ReturnData.success(Map.of("cardId", cardId, "name", name, "type", type));
    }

    /* ════════════════════════════════
       거래 목록
       ════════════════════════════════ */
    @GetMapping("/trades")
    public ReturnData<?> trades(
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "15") int size,
            @RequestParam(required = false)    String status,
            @RequestParam(required = false)    String search
    ) {
        StringBuilder where = new StringBuilder(" WHERE 1=1");
        if (status != null && !status.isBlank()) where.append(" AND t.status = :status");
        if (search != null && !search.isBlank()) where.append(" AND t.title LIKE :search");

        var countQ = em.createQuery("SELECT COUNT(t) FROM TradePost t" + where);
        var listQ  = em.createQuery("SELECT t FROM TradePost t" + where + " ORDER BY t.createdAt DESC");

        if (status != null && !status.isBlank()) {
            countQ.setParameter("status", status);
            listQ .setParameter("status", status);
        }
        if (search != null && !search.isBlank()) {
            countQ.setParameter("search", "%" + search + "%");
            listQ .setParameter("search", "%" + search + "%");
        }

        long total = ((Number) countQ.getSingleResult()).longValue();
        @SuppressWarnings("unchecked")
        List<?> rows = listQ.setFirstResult(page * size).setMaxResults(size).getResultList();

        List<Map<String, Object>> content = new ArrayList<>();
        for (Object obj : rows) {
            var t = (com.fury.back.domain.trade.TradePost) obj;
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("id",             t.getTradeId());
            m.put("title",          t.getTitle());
            m.put("authorNickname", t.getSellerId());
            m.put("tradeType",      "SELL");
            m.put("wantCardName",   t.getCardId());
            m.put("offerCardName",  null);
            m.put("status",         t.getStatus());
            m.put("createdAt",      t.getCreatedAt());
            content.add(m);
        }

        return ReturnData.success(Map.of(
            "content",       content,
            "totalElements", total,
            "totalPages",    (int) Math.ceil((double) total / size),
            "page",          page
        ));
    }

    /* ════════════════════════════════
       가격 이상 알림 (price_anomalies)
       ════════════════════════════════ */
    @GetMapping("/price-anomalies")
    public ReturnData<?> priceAnomalies(
            @RequestParam(defaultValue = "false") boolean resolved,
            @RequestParam(required = false) String date,   // YYYY-MM-DD 필터
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "30") int size
    ) {
        List<String> conditions = new ArrayList<>();
        if (!resolved) conditions.add("a.is_resolved = FALSE");
        if (date != null && date.matches("\\d{4}-\\d{2}-\\d{2}")) {
            conditions.add("a.detected_at::date = '" + date + "'");
        }
        String where = conditions.isEmpty() ? "" : " WHERE " + String.join(" AND ", conditions);

        long total = ((Number) em.createNativeQuery(
            "SELECT COUNT(*) FROM price_anomalies a" + where
        ).getSingleResult()).longValue();

        // 2026-05-29 P0 #3: enScrydexRef/jpScrydexRef/productId 추가 — 프론트 "원본 보기" 버튼용.
        //   resolution_type 추가 — 검토 완료 / 무시 구분 (V20260529 마이그레이션).
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery(
            "SELECT a.anomaly_id, a.card_id, c.name, a.source, a.detected_at, " +
            "a.reason, a.suspect_price_usd, a.hist_median_usd, a.ebay_result, a.is_resolved, a.resolved_at, " +
            "c.en_scrydex_ref, c.jp_scrydex_ref, c.product_id, a.resolution_type " +
            "FROM price_anomalies a JOIN cards c ON c.card_id = a.card_id" +
            where + " ORDER BY a.detected_at DESC"
        ).setFirstResult(page * size).setMaxResults(size).getResultList();

        List<Map<String, Object>> content = new ArrayList<>();
        for (Object[] r : rows) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("anomalyId",       r[0]);
            m.put("cardId",          r[1]);
            m.put("cardName",        r[2]);
            m.put("source",          r[3]);
            m.put("detectedAt",      r[4]);
            m.put("reason",          r[5]);
            m.put("suspectPriceUsd", r[6]);
            m.put("histMedianUsd",   r[7]);
            m.put("ebayResult",      r[8]);
            m.put("isResolved",      r[9]);
            m.put("resolvedAt",      r[10]);
            m.put("enScrydexRef",    r[11]);
            m.put("jpScrydexRef",    r[12]);
            m.put("productId",       r[13]);
            m.put("resolutionType",  r[14]);
            content.add(m);
        }
        return ReturnData.success(Map.of(
            "content",       content,
            "totalElements", total,
            "totalPages",    (int) Math.ceil((double) total / size),
            "page",          page
        ));
    }

    @GetMapping("/price-anomaly-dates")
    public ReturnData<?> anomalyDates() {
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery(
            "SELECT detected_at::date AS d, COUNT(*), SUM(CASE WHEN is_resolved THEN 1 ELSE 0 END) " +
            "FROM price_anomalies GROUP BY d ORDER BY d DESC LIMIT 60"
        ).getResultList();
        List<Map<String, Object>> result = new ArrayList<>();
        for (Object[] r : rows) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("date",          r[0].toString());
            m.put("total",         ((Number) r[1]).longValue());
            m.put("resolved",      ((Number) r[2]).longValue());
            m.put("unresolved",    ((Number) r[1]).longValue() - ((Number) r[2]).longValue());
            result.add(m);
        }
        return ReturnData.success(result);
    }

    /**
     * 2026-05-29 P0 #3 — body {action, memo?} 받음.
     *   action: REVIEWED (검토 완료) | DISMISSED (무시). null/missing → REVIEWED 기본.
     *   memo: DISMISSED 시 사유 권장 (frontend prompt).
     *   resolution_type 컬럼 (V20260529 마이그레이션) 에 저장 + admin_actions audit.
     */
    @PostMapping("/price-anomalies/{anomalyId}/resolve")
    @org.springframework.transaction.annotation.Transactional
    public ReturnData<?> resolveAnomaly(@PathVariable String anomalyId,
                                        @RequestBody(required = false) Map<String, String> body,
                                        @org.springframework.security.core.annotation.AuthenticationPrincipal String adminUserId) {
        String action = body != null ? body.getOrDefault("action", "REVIEWED") : "REVIEWED";
        String memo   = body != null ? body.get("memo") : null;
        if (!"REVIEWED".equals(action) && !"DISMISSED".equals(action)) {
            return ReturnData.badRequest("action 은 REVIEWED 또는 DISMISSED");
        }

        int updated = em.createNativeQuery(
            "UPDATE price_anomalies SET is_resolved = TRUE, resolved_at = NOW(), resolution_type = :rt " +
            "WHERE anomaly_id = :id"
        ).setParameter("rt", action).setParameter("id", anomalyId).executeUpdate();
        if (updated == 0) return ReturnData.notFound("anomaly not found: " + anomalyId);

        // admin_actions audit — 누가 언제 어느 anomaly 를 어떻게 처리했는지 영구 기록.
        if (adminUserId != null) {
            em.createNativeQuery(
                "INSERT INTO admin_actions (action_id, admin_user_id, action_type, target_type, target_id, memo, previous_state, new_state, created_at) " +
                "VALUES (:aid, :uid, :type, 'PRICE_ANOMALY', :tid, :memo, 'OPEN', :state, NOW())"
            ).setParameter("aid", "ACT_" + java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 20).toUpperCase())
             .setParameter("uid", adminUserId)
             .setParameter("type", "RESOLVE_ANOMALY_" + action)
             .setParameter("tid", anomalyId)
             .setParameter("memo", memo)
             .setParameter("state", "RESOLVED_" + action)
             .executeUpdate();
        }
        return ReturnData.success(Map.of("resolved", true, "action", action));
    }

    // eBay 정상 하락으로 확인된 항목 일괄 자동 처리
    @PostMapping("/price-anomalies/auto-resolve-accepted")
    @org.springframework.transaction.annotation.Transactional
    public ReturnData<?> autoResolveAccepted() {
        int updated = em.createNativeQuery(
            "UPDATE price_anomalies SET is_resolved = TRUE, resolved_at = NOW() " +
            "WHERE ebay_result = 'PRICE_DROP_ACCEPTED' AND is_resolved = FALSE"
        ).executeUpdate();
        return ReturnData.success(Map.of("autoResolved", updated));
    }

    /* ════════════════════════════════
       카드 조회 (추가 전 자동완성)
       ════════════════════════════════ */
    private static final Set<String> RARITY_SET = Set.of(
        "SAR","SSR","CSR","CHR","ACE","BWR","RRR","MUR","UR","AR","SR","RR","PR","HR","H","R","U","C"
    );
    private static final Pattern COL_NUM_PAT = Pattern.compile("\\b(\\d{1,3}/\\d{1,3})\\b");
    private static final Pattern RARITY_AFTER_COL_PAT = Pattern.compile("\\d{1,3}/\\d{1,3}\\s*([A-Za-z]{1,3})\\b");

    @GetMapping("/cards/lookup")
    public ReturnData<?> cardLookup(
            @RequestParam String type,
            @RequestParam String code
    ) {
        if (code == null || code.isBlank()) return ReturnData.badRequest("code는 필수입니다.");
        return switch (type.toUpperCase()) {
            case "KO" -> lookupKo(code.trim());
            case "EN" -> lookupScrydex(code.trim(), false);
            case "JP" -> lookupScrydex(code.trim(), true);
            default   -> ReturnData.badRequest("type은 KO/EN/JP 중 하나여야 합니다.");
        };
    }

    private ReturnData<?> lookupKo(String officialCardCode) {
        String url = "https://pokemoncard.co.kr/cards/detail/" + officialCardCode;
        try {
            Document doc = Jsoup.connect(url)
                .userAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
                .timeout(12_000)
                .get();

            // 카드명
            String name = "";
            Element titleSpan = doc.selectFirst("span.card-hp.title");
            if (titleSpan != null) name = titleSpan.text().trim();

            // 수록번호 + 희귀도
            String collectionNumber = null, rarityCode = null;
            Element pNum = doc.selectFirst("span.p_num");
            if (pNum != null) {
                String pText = pNum.text();
                Matcher m1 = COL_NUM_PAT.matcher(pText);
                if (m1.find()) collectionNumber = m1.group(1);

                Element noWrap = pNum.selectFirst("span#no_wrap_by_admin");
                if (noWrap != null) {
                    String rc = noWrap.text().trim().toUpperCase();
                    if (RARITY_SET.contains(rc)) rarityCode = rc;
                }
                if (rarityCode == null) {
                    Matcher m2 = RARITY_AFTER_COL_PAT.matcher(pText);
                    if (m2.find()) {
                        String cand = m2.group(1).toUpperCase();
                        if (RARITY_SET.contains(cand)) rarityCode = cand;
                    }
                }
            }

            // 세트명
            String productName = null;
            Element aTag = doc.selectFirst("div.pokemon-detail.txt_centre a.search_href");
            if (aTag != null) productName = aTag.text().trim();

            // DB에서 product_id 조회
            String productId = null;
            if (productName != null && !productName.isBlank()) {
                @SuppressWarnings("unchecked")
                List<String> rows = em.createQuery(
                    "SELECT p.productId FROM Product p WHERE p.name = :name", String.class)
                    .setParameter("name", productName)
                    .setMaxResults(1)
                    .getResultList();
                if (!rows.isEmpty()) {
                    productId = rows.get(0);
                } else {
                    // 첫 단어로 LIKE 검색
                    String firstWord = productName.split(" ")[0];
                    @SuppressWarnings("unchecked")
                    List<String> likeRows = em.createQuery(
                        "SELECT p.productId FROM Product p WHERE p.name LIKE :q ORDER BY p.name", String.class)
                        .setParameter("q", "%" + firstWord + "%")
                        .setMaxResults(1)
                        .getResultList();
                    if (!likeRows.isEmpty()) productId = likeRows.get(0);
                }
            }

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("name",             name);
            result.put("rarityCode",        rarityCode);
            result.put("collectionNumber",  collectionNumber);
            result.put("productName",       productName);
            result.put("productId",         productId);
            return ReturnData.success(result);

        } catch (org.jsoup.HttpStatusException e) {
            return ReturnData.notFound("포켓몬 코리아에서 카드를 찾을 수 없습니다: " + officialCardCode);
        } catch (Exception e) {
            return ReturnData.badRequest("조회 중 오류: " + e.getMessage());
        }
    }

    private ReturnData<?> lookupScrydex(String ref, boolean isJp) {
        String url = "https://scrydex.com/pokemon/cards/_/" + ref;
        try {
            Document doc = Jsoup.connect(url)
                .userAgent("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
                .timeout(12_000)
                .get();

            // title에서 카드명 추출: "Card Name | Scrydex" or "Card Name - Scrydex"
            String title = doc.title();
            String name = title;
            if (title.contains(" | ")) name = title.split(" \\| ")[0].trim();
            else if (title.contains(" - ")) name = title.split(" - ")[0].trim();

            // h1 fallback
            if (name.isBlank() || name.equalsIgnoreCase("scrydex")) {
                Element h1 = doc.selectFirst("h1");
                if (h1 != null) name = h1.text().trim();
            }

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("name",  name);
            result.put("valid", true);
            return ReturnData.success(result);

        } catch (org.jsoup.HttpStatusException e) {
            return ReturnData.notFound("Scrydex에서 카드를 찾을 수 없습니다: " + ref);
        } catch (Exception e) {
            return ReturnData.badRequest("조회 중 오류: " + e.getMessage());
        }
    }

    /* ════════════════════════════════
       시세 설정 (Price config는 기존 price 도메인 사용)
       ════════════════════════════════ */
    @GetMapping("/stats/scans/recent")
    public ReturnData<?> recentScans() {
        return ReturnData.success(List.of());
    }

    /* ════════════════════════════════
       스냅샷 수집 현황
       ════════════════════════════════ */
    @GetMapping("/stats/snapshots")
    public ReturnData<?> snapshotStats() {
        String today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE);
        String yesterday = LocalDate.now().minusDays(1).format(DateTimeFormatter.ISO_LOCAL_DATE);

        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createNativeQuery(
            "SELECT source, COUNT(*) AS cnt " +
            "FROM price_snapshots " +
            "WHERE traded_at >= CAST(:today AS timestamp) " +
            "  AND source IN ('SCRYDEX_EN','SCRYDEX_JP','KO_ESTIMATED','NAVER_CAFE','BUNJANG') " +
            "GROUP BY source ORDER BY source"
        ).setParameter("today", today + " 00:00:00").getResultList();

        @SuppressWarnings("unchecked")
        List<Object[]> rowsYest = em.createNativeQuery(
            "SELECT source, COUNT(*) AS cnt " +
            "FROM price_snapshots " +
            "WHERE traded_at >= CAST(:start AS timestamp) AND traded_at < CAST(:end AS timestamp) " +
            "  AND source IN ('SCRYDEX_EN','SCRYDEX_JP','KO_ESTIMATED','NAVER_CAFE','BUNJANG') " +
            "GROUP BY source ORDER BY source"
        ).setParameter("start", yesterday + " 00:00:00")
         .setParameter("end", today + " 00:00:00")
         .getResultList();

        Map<String, Long> todayCounts = new LinkedHashMap<>();
        for (Object[] r : rows) todayCounts.put((String) r[0], ((Number) r[1]).longValue());

        Map<String, Long> yesterdayCounts = new LinkedHashMap<>();
        for (Object[] r : rowsYest) yesterdayCounts.put((String) r[0], ((Number) r[1]).longValue());

        return ReturnData.success(Map.of(
            "today", todayCounts,
            "yesterday", yesterdayCounts,
            "date", today
        ));
    }

    /* ════════════════════════════════
       RAW/PSA10 비율 (PR-RATIO)
       ════════════════════════════════ */

    @GetMapping("/raw-psa10-ratios")
    public ReturnData<?> listRawPsa10Ratios() {
        List<RawPsa10Ratio> list = rawPsa10RatioRepository.findAllByOrderBySourceAscRarityCodeAsc();
        List<Map<String, Object>> rows = list.stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("source", r.getSource());
            m.put("rarityCode", r.getRarityCode());
            m.put("windowDays", r.getWindowDays());
            m.put("sampleCount", r.getSampleCount());
            m.put("ratioMedian", r.getRatioMedian());
            m.put("ratioP25", r.getRatioP25());
            m.put("ratioP75", r.getRatioP75());
            m.put("computedAt", r.getComputedAt());
            return m;
        }).toList();
        return ReturnData.success(Map.of("ratios", rows, "count", rows.size()));
    }

    /** 수동 재계산 — cron(매일 23:55) 안 기다리고 즉시 갱신. */
    @PostMapping("/raw-psa10-ratios/recompute")
    public ReturnData<?> recomputeRawPsa10Ratios() {
        var result = rawPsa10RatioCalculator.recalculate();
        return ReturnData.success(Map.of(
            "savedGroups", result.savedGroups(),
            "totalGroups", result.totalGroups()
        ));
    }
}
