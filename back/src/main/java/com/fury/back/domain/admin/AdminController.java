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

@lombok.extern.slf4j.Slf4j
@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminController {

    @PersistenceContext
    private EntityManager em;

    private final RawPsa10RatioCalculator rawPsa10RatioCalculator;
    private final RawPsa10RatioRepository rawPsa10RatioRepository;
    private final com.fury.back.domain.user.UserService userService;
    private final com.fury.back.storage.ImageStorageService imageStorage;
    private final AdminActionService adminActionService;
    private final com.fury.back.domain.card.CardService cardService;
    private final com.fury.back.domain.price.GlobalPriceService globalPriceService;

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

    /** 오늘 접속(DAU) + 접속중 — last_seen_at 기반(앱 유저만). 가입(stats/users.today)과 별개.
     *  접속중 = 최근 5분 활동 근사. last_seen_at 은 배포 후부터 쌓임(과거치 없음). */
    @GetMapping("/stats/active")
    public ReturnData<?> statsActive() {
        java.time.LocalDateTime todayStart = LocalDate.now().atStartOfDay();
        java.time.LocalDateTime onlineCut  = java.time.LocalDateTime.now().minusMinutes(5);
        long dauToday = ((Number) em.createQuery(
            "SELECT COUNT(u) FROM User u WHERE u.lastSeenAt >= :t AND u.deletedAt IS NULL")
            .setParameter("t", todayStart).getSingleResult()).longValue();
        long onlineNow = ((Number) em.createQuery(
            "SELECT COUNT(u) FROM User u WHERE u.lastSeenAt >= :t AND u.deletedAt IS NULL")
            .setParameter("t", onlineCut).getSingleResult()).longValue();
        return ReturnData.success(Map.of("dauToday", dauToday, "onlineNow", onlineNow));
    }

    /** 접속중(최근 5분) 유저 목록 — 닉네임. 대시보드 "접속중" 카드 클릭 시 "누구" 조회. */
    @GetMapping("/stats/active/online")
    public ReturnData<?> activeOnlineList() {
        return ReturnData.success(activeUserList(java.time.LocalDateTime.now().minusMinutes(5)));
    }

    /** 오늘 접속(DAU) 유저 목록 — 닉네임. "오늘 접속" 카드 클릭 시 조회. */
    @GetMapping("/stats/active/today")
    public ReturnData<?> activeTodayList() {
        return ReturnData.success(activeUserList(LocalDate.now().atStartOfDay()));
    }

    /** last_seen_at >= since 인 비삭제 유저 목록(닉네임 + 마지막 활동 시각), 최근순 최대 300명. */
    private List<Map<String, Object>> activeUserList(java.time.LocalDateTime since) {
        @SuppressWarnings("unchecked")
        List<Object[]> rows = em.createQuery(
                "SELECT u.userId, u.nickname, u.lastSeenAt FROM User u " +
                "WHERE u.lastSeenAt >= :t AND u.deletedAt IS NULL ORDER BY u.lastSeenAt DESC")
                .setParameter("t", since).setMaxResults(300).getResultList();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Object[] r : rows) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("userId", r[0]);
            m.put("nickname", r[1]);
            m.put("lastSeenAt", r[2] != null ? r[2].toString() : null);   // ISO 문자열 명시(프론트 상대시간 파싱)
            out.add(m);
        }
        return out;
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
            // 정지 상태 반영 — 하드코딩 "ACTIVE" 버그 fix. admin Users.jsx 는 status==='BANNED' || suspended 로 정지해제 버튼 노출.
            boolean suspended = u.isSuspended();
            m.put("status",          suspended ? "BANNED" : "ACTIVE");
            m.put("suspended",       suspended);
            m.put("suspensionReason", u.getSuspensionReason());
            // 2026-06-08: 탈퇴(deletedAt) 미반영 버그 fix — Users.jsx 가 deleted/deletedAt 로 "탈퇴" 표시 + 정지버튼 숨김.
            m.put("deleted",    u.getDeletedAt() != null);
            m.put("deletedAt",  u.getDeletedAt());
            // 스캔 = scan_captures(삭제 제외), 거래 = 판매글(삭제 제외) + 매수주문. 기존 하드코딩 0 버그 fix.
            String uid = u.getUserId();
            long scanCount = ((Number) em.createQuery(
                    "SELECT COUNT(s) FROM ScanCapture s WHERE s.userId = :uid AND s.deletedAt IS NULL")
                    .setParameter("uid", uid).getSingleResult()).longValue();
            long sellCount = ((Number) em.createQuery(
                    "SELECT COUNT(t) FROM TradePost t WHERE t.sellerId = :uid AND t.deletedAt IS NULL AND t.status <> 'DELETED'")
                    .setParameter("uid", uid).getSingleResult()).longValue();
            long buyCount = ((Number) em.createQuery(
                    "SELECT COUNT(b) FROM BuyOrder b WHERE b.buyerId = :uid AND b.status <> 'CANCELED'")
                    .setParameter("uid", uid).getSingleResult()).longValue();
            // 등록 카드 수 = 보유 자산(assets). 스캔으로 등록한 카드 = 이게 실제 사용량.
            // (scanCount=scan_captures는 학습동의 유저만 보관 → 0이어도 카드는 등록돼 있을 수 있음)
            long cardCount = ((Number) em.createQuery(
                    "SELECT COUNT(a) FROM Asset a WHERE a.userId = :uid")
                    .setParameter("uid", uid).getSingleResult()).longValue();
            m.put("cardCount",  cardCount);
            m.put("scanCount",  scanCount);
            m.put("tradeCount", sellCount + buyCount);
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
       탈퇴 유저 — 관리자 삭제 + 상세(원본 PII audit)
       ════════════════════════════════ */

    /** 관리자가 특정 유저 탈퇴 처리. deleteAccount 재사용 → 마스킹 전 원본 PII가 audit에 보존됨. */
    @PostMapping("/users/{userId}/delete")
    public ReturnData<?> deleteUser(@PathVariable String userId) {
        return userService.deleteAccount(userId);
    }

    /** 유저 상세 — 탈퇴자는 audit에서 원본 PII(admin 전용) + 보존된 활동 카운트. */
    @GetMapping("/users/{userId}")
    public ReturnData<?> userDetail(@PathVariable String userId) {
        var u = em.find(com.fury.back.domain.user.User.class, userId);
        if (u == null) return ReturnData.notFound("사용자를 찾을 수 없습니다. userId=" + userId);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id",        u.getUserId());
        m.put("createdAt", u.getCreatedAt());
        boolean deleted = u.getDeletedAt() != null;
        m.put("deleted",   deleted);
        m.put("deletedAt", u.getDeletedAt());
        if (deleted) {
            var a = em.find(com.fury.back.domain.user.DeletedUserAudit.class, userId);
            if (a != null) {
                m.put("originalNickname",        a.getOriginalNickname());
                m.put("originalEmail",           a.getOriginalEmail());
                m.put("originalProfileImageUrl", a.getOriginalProfileImageUrl());
                m.put("purgeAfter",              a.getPurgeAfter());
            }
            m.put("maskedNickname", u.getNickname());
        } else {
            m.put("nickname", u.getNickname());
            m.put("email",    u.getEmail());
            // 확장 정보 — native 조회(Lombok boolean getter 네이밍 회피, 기존 카운트 쿼리와 동일 스타일).
            Object[] r = (Object[]) em.createNativeQuery(
                    "SELECT google_id, apple_id, suspended_at, suspension_reason, " +
                    "phone_verified, phone_e164, phone_verified_at, is_over_14, age_checked_at, " +
                    "onboarded, scan_image_consent, scan_image_consent_at " +
                    "FROM users WHERE user_id = :uid")
                    .setParameter("uid", userId).getSingleResult();
            m.put("provider",           r[0] != null ? "GOOGLE" : (r[1] != null ? "APPLE" : "-"));
            m.put("suspended",          r[2] != null);
            m.put("suspendedAt",        toLdt(r[2]));
            m.put("suspensionReason",   r[3]);
            m.put("phoneVerified",      r[4]);
            m.put("phoneE164",          maskPhone((String) r[5]));
            m.put("phoneVerifiedAt",    toLdt(r[6]));
            m.put("isOver14",           r[7]);
            m.put("ageCheckedAt",       toLdt(r[8]));
            m.put("onboarded",          r[9]);
            m.put("scanImageConsent",   r[10]);
            m.put("scanImageConsentAt", toLdt(r[11]));
        }
        // 보존된 활동 (탈퇴해도 안 지워짐).
        m.put("assetCount",       auditCount("SELECT COUNT(*) FROM assets WHERE user_id=:uid", userId));
        m.put("tradePostCount",   auditCount("SELECT COUNT(*) FROM trade_posts WHERE seller_id=:uid", userId));
        m.put("buyOrderCount",    auditCount("SELECT COUNT(*) FROM buy_orders WHERE buyer_id=:uid", userId));
        m.put("scanCaptureCount", auditCount("SELECT COUNT(*) FROM scan_captures WHERE user_id=:uid AND deleted_at IS NULL", userId));
        return ReturnData.success(m);
    }

    private long auditCount(String sql, String userId) {
        return ((Number) em.createNativeQuery(sql).setParameter("uid", userId).getSingleResult()).longValue();
    }

    /** native 쿼리 timestamp → LocalDateTime. ★Hibernate 6은 timestamp 컬럼을 LocalDateTime으로 반환할 수
        있어 직접 (Timestamp) 캐스트는 ClassCastException → instanceof로 처리(기존 toIso와 동일 패턴). */
    private Object toLdt(Object o) {
        if (o instanceof Timestamp ts) return ts.toLocalDateTime();
        return o; // 이미 LocalDateTime/Instant 이거나 null — Jackson ISO 직렬화.
    }

    /** 휴대폰 번호 마스킹 — admin 화면 노출용(+821012345678 → 010-****-5678). */
    private String maskPhone(String e164) {
        if (e164 == null || e164.isBlank()) return null;
        String d = e164.replaceAll("[^0-9]", "");
        if (d.startsWith("82")) d = "0" + d.substring(2);
        if (d.length() < 8) return "***";
        return d.substring(0, 3) + "-****-" + d.substring(d.length() - 4);
    }

    /**
     * 유저 스캔 캡처 목록 + 실제 스캔 사진(presigned, TTL 10분). 동의(scan_image_consent) 유저만 사진 보관.
     * ★실제 PII(스캔 사진) 열람이므로 AdminAction(VIEW_USER_SCANS) 감사 기록 — 유저에겐 노출/통지 X(내부 기록).
     */
    @GetMapping("/users/{userId}/scans")
    @SuppressWarnings("unchecked")
    public ReturnData<?> userScans(@PathVariable String userId,
                                   @org.springframework.security.core.annotation.AuthenticationPrincipal String adminUserId) {
        var u = em.find(com.fury.back.domain.user.User.class, userId);
        if (u == null) return ReturnData.notFound("사용자를 찾을 수 없습니다. userId=" + userId);

        List<Object[]> rows = em.createNativeQuery(
                "SELECT s.capture_id, s.card_id, c.name, s.s3_key, s.match_confidence, " +
                "s.image_quality, s.created_at, s.consent_version " +
                "FROM scan_captures s LEFT JOIN cards c ON c.card_id = s.card_id " +
                "WHERE s.user_id = :uid AND s.deleted_at IS NULL ORDER BY s.created_at DESC")
                .setParameter("uid", userId).getResultList();

        List<Map<String, Object>> scans = new ArrayList<>();
        for (Object[] r : rows) {
            Map<String, Object> sm = new LinkedHashMap<>();
            sm.put("captureId",       r[0]);
            sm.put("cardId",          r[1]);
            sm.put("cardName",        r[2]);
            try {
                sm.put("imageUrl", imageStorage.presignedGetUrl((String) r[3], Duration.ofMinutes(10)));
            } catch (Exception e) {
                sm.put("imageUrl", null); // 한 장 실패가 전체 막지 않게.
            }
            sm.put("matchConfidence", r[4]);
            sm.put("imageQuality",    r[5]);
            sm.put("createdAt",       toLdt(r[6]));
            sm.put("consentVersion",  r[7]);
            scans.add(sm);
        }

        // 스캔 데이터 열람 시도 자체를 감사 기록(빈 목록 포함 — 접근 사실이 audit 대상).
        // adminUserId null(로컬 admin-auth bypass)이면 NOT NULL 제약 회피 위해 UNKNOWN.
        String actor = (adminUserId == null || adminUserId.isBlank()) ? "UNKNOWN" : adminUserId;
        adminActionService.record(actor, "VIEW_USER_SCANS", "USER", userId,
                null, scans.size() + "장 스캔 이미지 열람", null, null);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scans", scans);
        return ReturnData.success(out);
    }

    /**
     * 유저가 등록한 카드(보유 자산) 목록 + 등록 시 찍은 실제 사진(asset_images, presigned TTL 10분).
     * ★asset_images는 앱 기능상 항상 저장 → scan_image_consent(모델 학습 동의)와 무관하게 admin 열람 가능.
     * (학습용 raw 이미지=scan_captures는 /scans 별도.) 사용자 사진 열람이므로 VIEW_USER_ASSETS 감사 기록.
     */
    @GetMapping("/users/{userId}/assets")
    @SuppressWarnings("unchecked")
    public ReturnData<?> userAssets(@PathVariable String userId,
                                    @org.springframework.security.core.annotation.AuthenticationPrincipal String adminUserId) {
        var u = em.find(com.fury.back.domain.user.User.class, userId);
        if (u == null) return ReturnData.notFound("사용자를 찾을 수 없습니다. userId=" + userId);

        // assets × asset_images LEFT JOIN — 자산당 이미지(FRONT/BACK/SLAB) 여러 row. cards.is_visible 제약은
        // native 라 우회(admin은 숨김카드 등록 자산도 봐야 함). 과대 포트폴리오 방지 row LIMIT 500.
        List<Object[]> rows = em.createNativeQuery(
                "SELECT a.asset_id, a.card_id, c.name, c.rarity_code, a.language, a.card_status, " +
                "a.grading_company, a.grade_value, a.estimated_grade, a.created_at, " +
                "ai.image_id, ai.image_type, ai.image_url " +
                "FROM assets a LEFT JOIN cards c ON c.card_id = a.card_id " +
                "LEFT JOIN asset_images ai ON ai.asset_id = a.asset_id " +
                "WHERE a.user_id = :uid ORDER BY a.created_at DESC, ai.image_type LIMIT 500")
                .setParameter("uid", userId).getResultList();

        Map<String, Map<String, Object>> assetMap = new LinkedHashMap<>();
        for (Object[] r : rows) {
            String assetId = (String) r[0];
            Map<String, Object> am = assetMap.computeIfAbsent(assetId, id -> {
                Map<String, Object> a = new LinkedHashMap<>();
                a.put("assetId",        id);
                a.put("cardId",         r[1]);
                a.put("cardName",       r[2]);
                a.put("rarity",         r[3]);
                a.put("language",       r[4]);
                a.put("cardStatus",     r[5]);
                a.put("gradingCompany", r[6]);
                a.put("gradeValue",     r[7]);
                a.put("estimatedGrade", r[8]);
                a.put("createdAt",      toLdt(r[9]));
                a.put("images",         new ArrayList<Map<String, Object>>());
                return a;
            });
            if (r[10] != null) { // image_id not null = 이미지 존재
                String key = (String) r[12];
                String url;
                if (key != null && !key.startsWith("/") && !key.startsWith("http")) {
                    try { url = imageStorage.presignedGetUrl(key, Duration.ofMinutes(10)); }
                    catch (Exception e) { url = null; } // 한 장 실패가 전체 막지 않게
                } else {
                    url = key; // legacy full-url 또는 null
                }
                Map<String, Object> img = new LinkedHashMap<>();
                img.put("imageType", r[11]);
                img.put("imageUrl",  url);
                ((List<Map<String, Object>>) am.get("images")).add(img);
            }
        }
        List<Map<String, Object>> assets = new ArrayList<>(assetMap.values());

        // 사용자 실물 사진 열람 감사 — scan_image_consent와 무관하나 PII 준함.
        String actor = (adminUserId == null || adminUserId.isBlank()) ? "UNKNOWN" : adminUserId;
        adminActionService.record(actor, "VIEW_USER_ASSETS", "USER", userId,
                null, assets.size() + "개 등록카드 열람", null, null);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("assets", assets);
        return ReturnData.success(out);
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
            // 카드별 스캔수 = scan_captures(삭제 제외) of this card. 기존 하드코딩 0 버그 fix.
            m.put("scanCount",  ((Number) em.createQuery(
                    "SELECT COUNT(s) FROM ScanCapture s WHERE s.cardId = :cid AND s.deletedAt IS NULL")
                    .setParameter("cid", c.getCardId()).getSingleResult()).longValue());
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
       카드 추가 전 미리보기 — 예상가 + 투영 차트 (DB 무영속 dry-run)
       ════════════════════════════════ */
    @PostMapping("/cards/preview")
    public ReturnData<?> previewCard(@RequestBody Map<String, Object> body) {
        String rarityCode = (String) body.get("rarityCode");
        String productId  = (String) body.get("productId");
        String enRef      = (String) body.get("enScrydexRef");
        String jpRef      = (String) body.get("jpScrydexRef");
        try {
            return ReturnData.success(globalPriceService.previewCardAdd(rarityCode, productId, enRef, jpRef));
        } catch (Exception e) {
            log.warn("[Admin] 카드 미리보기 실패: {}", e.getMessage());
            return ReturnData.badRequest("미리보기 실패: " + e.getMessage());
        }
    }

    /* ════════════════════════════════
       카드 추가 (KO/EN/JP 3가지 타입)
       ════════════════════════════════ */
    @PostMapping("/cards")
    public ReturnData<?> addCard(@RequestBody Map<String, Object> body) {
        String type        = (String) body.get("type");        // KO | EN | JP
        String name        = (String) body.get("name");
        String productId   = (String) body.get("productId");
        String rarityCode  = (String) body.get("rarityCode");
        String colNumber   = (String) body.get("collectionNumber");
        String superType   = body.get("superType") != null ? body.get("superType").toString() : "POKEMON";
        String subType     = (String) body.get("subType");
        String officialCode = (String) body.get("officialCardCode");
        String enRef       = (String) body.get("enScrydexRef");
        String jpRef       = (String) body.get("jpScrydexRef");

        if (name == null || name.isBlank())      return ReturnData.badRequest("name은 필수입니다.");
        if (productId == null || productId.isBlank()) return ReturnData.badRequest("productId는 필수입니다.");
        if (rarityCode == null || rarityCode.isBlank()) return ReturnData.badRequest("rarityCode는 필수입니다.");

        // 중복 체크: officialCardCode. ★네이티브 — JPQL은 Card @SQLRestriction(is_visible=true) 적용돼
        // 숨김(visible=false) 카드 같은 코드를 못 잡아 INSERT 후 충돌함. native 로 visible 무관 전수 확인.
        if (officialCode != null && !officialCode.isBlank()) {
            Number dup = (Number) em.createNativeQuery(
                "SELECT COUNT(*) FROM cards WHERE official_card_code = :code")
                .setParameter("code", officialCode).getSingleResult();
            if (dup.longValue() > 0) return ReturnData.badRequest("이미 존재하는 officialCardCode: " + officialCode);
        }

        // 1) INSERT 만 별도 트랜잭션에서 커밋 (cardService — 프록시 경유라 메서드 반환 시 커밋 완료)
        var req = new com.fury.back.domain.card.AdminAddCardRequest(
                type, name, productId, rarityCode, colNumber, superType, subType, officialCode, enRef, jpRef);
        Map<String, Object> out;
        try {
            out = new LinkedHashMap<>(cardService.addCardFromAdmin(req));
        } catch (IllegalArgumentException e) {
            return ReturnData.badRequest(e.getMessage());
        }
        String cardId = (String) out.get("cardId");

        // 2) 커밋 후 보강(이미지+KO 예상가). ★실패해도 카드 추가는 유지 — try-catch 격리(틱 교훈).
        try {
            Map<String, Object> enrich = cardService.enrichCardAfterAdd(cardId, enRef, jpRef);
            out.put("enriched", true);
            out.put("images", enrich.get("images"));
            out.put("priceFetch", enrich.get("priceFetch"));
        } catch (Exception e) {
            log.warn("[Admin] 카드 추가 후 보강 실패(카드는 저장됨) cardId={}: {}", cardId, e.getMessage());
            out.put("enriched", false);
            out.put("enrichError", e.getMessage());
        }
        return ReturnData.success(out);
    }

    /* ════════════════════════════════
       A: 시리즈(세트) 일괄추가 — KO (pokemoncard 순차 walk)
       ════════════════════════════════ */

    /** prefix 형식: 영문2 + 숫자7 (예 BS2026003 = BS+연도4+세트seq3). 카드번호 3자리는 walk가 부여. */
    private static final Pattern KO_SET_PREFIX_PAT = Pattern.compile("^[A-Za-z]{2}\\d{7}$");

    /** ★저레어 — 카탈로그 정책상 제외: C/U/R = row 삭제(legacy commons), S/K = 감춤. chase 레어도만 노출.
     *  일괄추가 기본 제외 (admin이 명시 override 시에만 추가). null(파싱실패)도 자동추가 안 함. */
    private static final java.util.Set<String> LOW_RARITY_SET = java.util.Set.of("C", "U", "R", "S", "K");

    /**
     * 세트 일괄추가 1단계 — 미리보기(dry-run). pokemoncard `/cards/detail/{prefix}{번호:03d}` 순차 조회.
     * 빈 카드(parseKoDetail==null)가 maxGap 연속이면 세트 끝으로 보고 종료. 기존 DB와 dedup(exists 플래그).
     * ★실제 INSERT 안 함 — bulk-insert 에서. scrydex 와 무관(KO 전용 소스).
     */
    @GetMapping("/cards/bulk-preview")
    public ReturnData<?> bulkPreview(
            @RequestParam String prefix,
            @RequestParam(defaultValue = "5")   int maxGap,
            @RequestParam(defaultValue = "300") int maxCards) {
        if (prefix == null || !KO_SET_PREFIX_PAT.matcher(prefix).matches())
            return ReturnData.badRequest("prefix 형식 오류 (예: BS2026003)");
        if (maxCards > 400) maxCards = 400;   // 안전 상한 (외부 사이트 과호출 방지)
        if (maxGap   > 20)  maxGap   = 20;

        List<Map<String, Object>> rows = new ArrayList<>();
        int gap = 0, found = 0, existing = 0;
        for (int n = 1; n <= maxCards && gap < maxGap; n++) {
            String code = prefix + String.format("%03d", n);
            try {
                Document doc = Jsoup.connect("https://pokemoncard.co.kr/cards/detail/" + code)
                    .userAgent(PC_UA).timeout(8_000).get();
                Map<String, Object> p = parseKoDetail(doc);
                if (p == null) { gap++; continue; }
                gap = 0; found++;
                boolean exists = ((Number) em.createQuery(
                    "SELECT COUNT(c) FROM Card c WHERE c.officialCardCode = :code")
                    .setParameter("code", code).getSingleResult()).longValue() > 0;
                if (exists) existing++;
                String rc = (String) p.get("rarityCode");
                p.put("lowRarity", rc == null || LOW_RARITY_SET.contains(rc));  // 정책상 제외 후보
                p.put("officialCardCode", code);
                p.put("exists", exists);
                rows.add(p);
            } catch (Exception e) {
                gap++;   // 네트워크/404 등도 gap 으로 (연속이면 종료)
            }
            try { Thread.sleep(120); }   // politeness — 외부 사이트 과호출 방지
            catch (InterruptedException ie) { Thread.currentThread().interrupt(); break; }
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("prefix",   prefix);
        out.put("found",    found);
        out.put("existing", existing);
        out.put("newCount", found - existing);
        out.put("cards",    rows);
        return ReturnData.success(out);
    }

    /**
     * 세트 일괄추가 2단계 — 확정 카드 INSERT. body = {productId(세트, 일괄적용 필수), cards:[{officialCardCode,name,rarityCode,collectionNumber}]}.
     * ★멱등: officialCardCode 이미 있으면 skip. 세트 1개 단위라 productId 는 admin 이 한번 선택해 전체 적용.
     * 이미지는 미포함(KO 전용 — scrydex 매칭 시 별도 미러, 현 KO-exclusive 동작과 동일).
     */
    @PostMapping("/cards/bulk-insert")
    @org.springframework.transaction.annotation.Transactional
    public ReturnData<?> bulkInsert(@RequestBody Map<String, Object> body) {
        String productId = (String) body.get("productId");
        if (productId == null || productId.isBlank())
            return ReturnData.badRequest("productId(세트)는 필수입니다.");
        boolean allowLowRarity = Boolean.TRUE.equals(body.get("allowLowRarity"));  // 명시 override만
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> cards = (List<Map<String, Object>>) body.get("cards");
        if (cards == null || cards.isEmpty())
            return ReturnData.badRequest("cards 가 비었습니다.");

        // N+1 제거(Codex P1): 기존 officialCardCode 한 번에 조회 → Set 멱등 체크
        List<String> allCodes = new ArrayList<>();
        for (Map<String, Object> c : cards) {
            Object code = c.get("officialCardCode");
            if (code instanceof String s && !s.isBlank()) allCodes.add(s);
        }
        java.util.Set<String> existingCodes = allCodes.isEmpty() ? java.util.Set.of()
            : new java.util.HashSet<>(em.createQuery(
                "SELECT c.officialCardCode FROM Card c WHERE c.officialCardCode IN :codes", String.class)
                .setParameter("codes", allCodes).getResultList());

        int inserted = 0, skipped = 0;
        List<String> errors = new ArrayList<>();
        var now = java.time.LocalDateTime.now();
        for (Map<String, Object> c : cards) {
            String code       = (String) c.get("officialCardCode");
            String name       = (String) c.get("name");
            String rarityCode = (String) c.get("rarityCode");
            String colNumber  = (String) c.get("collectionNumber");
            if (code == null || code.isBlank() || name == null || name.isBlank()) { skipped++; continue; }
            if (rarityCode == null || rarityCode.isBlank()) { errors.add(code + ": 레어도 없음"); continue; }
            // ★저레어 서버 가드(정책): C/U/R/S/K 는 override 없으면 skip (FE 기본 미선택 + 이중 방어)
            if (!allowLowRarity && LOW_RARITY_SET.contains(rarityCode)) { skipped++; continue; }
            if (existingCodes.contains(code)) { skipped++; continue; }

            String cardId = "CRD_" + java.util.UUID.randomUUID().toString().replace("-", "").toUpperCase();
            em.createNativeQuery("""
                INSERT INTO cards (card_id, product_id, official_card_code, name, collection_number,
                  rarity_code, language, super_type, sub_type, card_type,
                  en_scrydex_ref, jp_scrydex_ref, is_promo_exclusive, created_at, updated_at)
                VALUES (?,?,?,?,?,?, 'KO', 'POKEMON', NULL, NULL, NULL, NULL, false, ?, ?)
                """)
                .setParameter(1, cardId).setParameter(2, productId)
                .setParameter(3, code).setParameter(4, name)
                .setParameter(5, colNumber).setParameter(6, rarityCode)
                .setParameter(7, now).setParameter(8, now)
                .executeUpdate();
            inserted++;
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("inserted", inserted);
        out.put("skipped",  skipped);
        out.put("errors",   errors);
        out.put("productId", productId);
        return ReturnData.success(out);
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
        // 탭 → 엔티티별 원시 status. 전체(=null)는 DELETED 제외. 판매(TradePost)+매수(BuyOrder) 합침.
        String tab = (status == null || status.isBlank()) ? "ALL" : status;
        List<String> tpSt, boSt;
        switch (tab) {
            case "ACTIVE"    -> { tpSt = List.of("OPEN", "RESERVED"); boSt = List.of("OPEN"); }
            case "COMPLETED" -> { tpSt = List.of("COMPLETED");        boSt = List.of("MATCHED"); }
            case "CANCELLED" -> { tpSt = List.of("CANCELED");         boSt = List.of("CANCELED"); }
            case "DELETED"   -> { tpSt = List.of("DELETED");          boSt = List.of(); }
            default          -> { tpSt = List.of("OPEN", "RESERVED", "COMPLETED", "CANCELED");  // 전체 = DELETED 제외
                                  boSt = List.of("OPEN", "MATCHED", "CANCELED"); }
        }

        List<Map<String, Object>> all = new ArrayList<>();
        if (!tpSt.isEmpty()) {
            for (var t : em.createQuery(
                    "SELECT t FROM TradePost t WHERE t.status IN :st ORDER BY t.createdAt DESC",
                    com.fury.back.domain.trade.TradePost.class).setParameter("st", tpSt).getResultList()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id",             t.getTradeId());
                m.put("title",          t.getTitle());
                m.put("authorNickname", t.getSellerId());
                m.put("tradeType",      "SELL");
                m.put("wantCardName",   t.getCardId());
                m.put("offerCardName",  null);
                m.put("status",         normTradeStatus(t.getStatus(), false));
                m.put("createdAt",      t.getCreatedAt());
                all.add(m);
            }
        }
        if (!boSt.isEmpty()) {
            for (var b : em.createQuery(
                    "SELECT b FROM BuyOrder b WHERE b.status IN :st ORDER BY b.createdAt DESC",
                    com.fury.back.domain.trade.BuyOrder.class).setParameter("st", boSt).getResultList()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("id",             b.getBuyOrderId());
                m.put("title",          "[매수] " + b.getCardId());
                m.put("authorNickname", b.getBuyerId());
                m.put("tradeType",      "BUY");
                m.put("wantCardName",   b.getCardId());
                m.put("offerCardName",  null);
                m.put("status",         normTradeStatus(b.getStatus(), true));
                m.put("createdAt",      b.getCreatedAt());
                all.add(m);
            }
        }
        // 제목 검색(판매·매수 통합 post-filter)
        if (search != null && !search.isBlank()) {
            String s = search.toLowerCase(java.util.Locale.ROOT);
            all.removeIf(m -> {
                Object tt = m.get("title");
                return tt == null || !tt.toString().toLowerCase(java.util.Locale.ROOT).contains(s);
            });
        }
        all.sort((a, b) -> {
            var ca = (java.time.LocalDateTime) a.get("createdAt");
            var cb = (java.time.LocalDateTime) b.get("createdAt");
            if (ca == null && cb == null) return 0;
            if (ca == null) return 1;
            if (cb == null) return -1;
            return cb.compareTo(ca);
        });
        long total = all.size();
        int from = Math.min(page * size, all.size());
        int to   = Math.min(from + size, all.size());
        List<Map<String, Object>> content = new ArrayList<>(all.subList(from, to));

        return ReturnData.success(Map.of(
            "content",       content,
            "totalElements", total,
            "totalPages",    (int) Math.ceil((double) total / size),
            "page",          page
        ));
    }

    /** 판매(TradePost)/매수(BuyOrder) 원시 status → 프론트 표시 그룹(ACTIVE/COMPLETED/CANCELLED/DELETED). */
    private String normTradeStatus(String s, boolean isBuyOrder) {
        if (s == null) return "ACTIVE";
        if (isBuyOrder) {
            return switch (s) { case "MATCHED" -> "COMPLETED"; case "CANCELED" -> "CANCELLED"; default -> "ACTIVE"; };
        }
        return switch (s) {
            case "COMPLETED" -> "COMPLETED";
            case "CANCELED"  -> "CANCELLED";
            case "DELETED"   -> "DELETED";
            default          -> "ACTIVE";
        };
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

    /** scrydex rarity(JP 카타카나/EN) → 앱 rarity_code. 미매칭은 null → admin 수동선택.
     *  (2026-06-14 스마트 카드추가 B2 — 확실한 것만, 모호하면 안 넣음) */
    private static final Map<String, String> RARITY_MAP = Map.ofEntries(
        Map.entry("PROMO", "PR"),                  Map.entry("プロモ", "PR"),
        Map.entry("DOUBLE RARE", "RR"),            Map.entry("ダブルレア", "RR"),
        Map.entry("TRIPLE RARE", "RRR"),           Map.entry("トリプルレア", "RRR"),
        Map.entry("ART RARE", "AR"),               Map.entry("アートレア", "AR"),
        Map.entry("ILLUSTRATION RARE", "AR"),
        Map.entry("SPECIAL ART RARE", "SAR"),      Map.entry("スペシャルアートレア", "SAR"),
        Map.entry("SPECIAL ILLUSTRATION RARE", "SAR"),
        Map.entry("SUPER RARE", "SR"),             Map.entry("スーパーレア", "SR"),
        Map.entry("HYPER RARE", "HR"),             Map.entry("ハイパーレア", "HR"),
        Map.entry("ULTRA RARE", "UR"),             Map.entry("ウルトラレア", "UR"),
        Map.entry("RARE", "R"),                    Map.entry("レア", "R"),
        Map.entry("UNCOMMON", "U"),                Map.entry("アンコモン", "U"),
        Map.entry("COMMON", "C"),                  Map.entry("コモン", "C")
    );

    /** scrydex expansion.name → KO 세트명(Product.name 조회용). 미매칭은 scrydex 원문 그대로 + productId null.
     *  (초기 상수, 늘면 DB 테이블로 이전 — Codex 권고) */
    private static final Map<String, String> SCRYDEX_SET_MAP = Map.ofEntries(
        Map.entry("Sun & Moon Promos", "썬&문 프로모"),
        Map.entry("Sword & Shield Promos", "소드&실드 프로모"),
        Map.entry("Scarlet & Violet Promos", "스칼렛&바이올렛 프로모"),
        Map.entry("SVP Black Star Promos", "스칼렛&바이올렛 프로모"),
        Map.entry("SWSH Black Star Promos", "소드&실드 프로모")
    );

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

    private static final String PC_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36";

    private ReturnData<?> lookupKo(String officialCardCode) {
        String url = "https://pokemoncard.co.kr/cards/detail/" + officialCardCode;
        try {
            Document doc = Jsoup.connect(url).userAgent(PC_UA).timeout(12_000).get();
            Map<String, Object> parsed = parseKoDetail(doc);
            if (parsed == null)
                return ReturnData.notFound("포켓몬 코리아에서 카드를 찾을 수 없습니다: " + officialCardCode);
            return ReturnData.success(parsed);
        } catch (org.jsoup.HttpStatusException e) {
            return ReturnData.notFound("포켓몬 코리아에서 카드를 찾을 수 없습니다: " + officialCardCode);
        } catch (Exception e) {
            return ReturnData.badRequest("조회 중 오류: " + e.getMessage());
        }
    }

    /** pokemoncard 카드 상세 DOM 파싱 → {name,rarityCode,collectionNumber,productName,productId}.
     *  ★이름 없으면 null = 빈 카드(범위밖) → A 세트 walk 의 종료 신호로도 사용. lookupKo/bulkPreview 공용. */
    private Map<String, Object> parseKoDetail(Document doc) {
        String name = "";
        Element titleSpan = doc.selectFirst("span.card-hp.title");
        if (titleSpan != null) name = titleSpan.text().trim();
        if (name.isBlank()) return null;

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

        String productName = null;
        Element aTag = doc.selectFirst("div.pokemon-detail.txt_centre a.search_href");
        if (aTag != null) productName = aTag.text().trim();

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("name",             name);
        result.put("rarityCode",        rarityCode);
        result.put("collectionNumber",  collectionNumber);
        result.put("productName",       productName);
        result.put("productId",         resolveProductId(productName));  // exact-only (Codex P1)
        return result;
    }

    /** scrydex ref 패턴 (예 smp_ja-407, sv8pt5_en-...). 경로조작/오염 차단(Codex P1 SSRF). */
    private static final Pattern SCRYDEX_REF_PAT = Pattern.compile("^[a-z0-9_\\-]{3,40}$");

    private ReturnData<?> lookupScrydex(String ref, boolean isJp) {
        if (ref == null || !SCRYDEX_REF_PAT.matcher(ref).matches())
            return ReturnData.badRequest("유효하지 않은 scrydex ref 형식");
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

            // ── B2 (2026-06-14): data-field 값 추출 → 전체 auto-fill ──
            //   ★[data-field=X] 직접은 '라벨'(예 "rarity"), 값은 그 parent의 .text-body-16 (실측 확인)
            String rawRarity = scrydexField(doc, "rarity");        // 표시패널 값 (예 "Promo")
            String rarityCode = null;
            if (rawRarity != null) {
                rarityCode = RARITY_MAP.get(rawRarity.toUpperCase());   // EN
                if (rarityCode == null) rarityCode = RARITY_MAP.get(rawRarity); // JP 카타카나 fallback
            }

            String collectionNumber = scrydexField(doc, "printed_number");
            String seriesName       = scrydexField(doc, "expansion.series");

            // 세트: scrydex expansion.name → KO 세트명 매핑 → productId 조회 (미매칭은 원문+null)
            String productName = null, productId = null;
            String scrydexSet = scrydexField(doc, "expansion.name");
            if (scrydexSet != null) {
                productName = SCRYDEX_SET_MAP.getOrDefault(scrydexSet, scrydexSet);
                productId   = resolveProductId(productName);
            }

            // 이미지: og:image 우선, 없으면 scrydex CDN 패턴
            String imageUrl = null;
            Element ogImg = doc.selectFirst("meta[property='og:image']");
            if (ogImg != null) imageUrl = ogImg.attr("content");
            if (imageUrl == null || imageUrl.isBlank())
                imageUrl = "https://images.scrydex.com/pokemon/" + ref + "/medium";

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("name",             name);
            result.put("valid",            true);
            result.put("rarityCode",        rarityCode);
            result.put("collectionNumber",  collectionNumber);
            result.put("productName",       productName);
            result.put("productId",         productId);
            result.put("seriesName",        seriesName);
            result.put("imageUrl",          imageUrl);
            result.put("language",          isJp ? "JP" : "EN");
            return ReturnData.success(result);

        } catch (org.jsoup.HttpStatusException e) {
            return ReturnData.notFound("Scrydex에서 카드를 찾을 수 없습니다: " + ref);
        } catch (Exception e) {
            return ReturnData.badRequest("조회 중 오류: " + e.getMessage());
        }
    }

    /** KO 세트명 → Product.productId. ★exact 매칭만(Codex 리뷰 P1): 첫단어 LIKE fallback은
     *  오매핑(잘못된 세트→가격/그룹 오류) 위험 — 실패 시 null 반환, admin이 수동 선택. */
    private String resolveProductId(String productName) {
        if (productName == null || productName.isBlank()) return null;
        String norm = productName.trim().replaceAll("\\s+", " ");  // 스크랩 공백 정규화 (오매핑 없이 exact 매칭률↑)
        List<String> rows = em.createQuery(
                "SELECT p.productId FROM Product p WHERE p.name = :name", String.class)
            .setParameter("name", norm).setMaxResults(1).getResultList();
        return rows.isEmpty() ? null : rows.get(0);
    }

    /** ★문의 자동화: KO 세트명+번호 → BS 오피셜코드 유추. 세트의 기존 카드 official_card_code prefix(9자=BS+연도4+seq3) + 번호3자리.
     *  (초전브레이커 + 109/SV8 → 기존 BS2024017xxx → BS2024017109). 문의 카드추가 자동조회용. */
    @GetMapping("/cards/derive-ko-code")
    public ReturnData<?> deriveKoCode(@RequestParam String productName, @RequestParam String number) {
        Matcher nm = Pattern.compile("^(\\d{1,3})").matcher(number == null ? "" : number.trim());
        if (!nm.find()) return ReturnData.badRequest("번호 형식 오류");
        String num  = String.format("%03d", Integer.parseInt(nm.group(1)));
        String norm = productName == null ? "" : productName.trim().replaceAll("\\s+", " ");
        String jpql = "SELECT c.officialCardCode FROM Card c, Product p WHERE c.productId = p.productId "
                    + "AND p.name %s AND c.officialCardCode <> '' AND LENGTH(c.officialCardCode) >= 12 ORDER BY c.officialCardCode";
        List<String> codes = em.createQuery(String.format(jpql, "= :pn"), String.class)
            .setParameter("pn", norm).setMaxResults(1).getResultList();
        if (codes.isEmpty())   // exact 실패 → LIKE fallback
            codes = em.createQuery(String.format(jpql, "LIKE :pn"), String.class)
                .setParameter("pn", "%" + norm + "%").setMaxResults(1).getResultList();
        if (codes.isEmpty()) return ReturnData.notFound("세트의 기존 카드가 없어 코드 유추 불가");
        return ReturnData.success(Map.of("code", codes.get(0).substring(0, 9) + num));
    }

    /** scrydex 카드 상세에서 data-field 값 추출. [data-field=X]는 숨김 '라벨'이라,
     *  그 parent 의 .text-body-16(표시값)을 읽는다. (2026-06-14 실측 확인)
     *  방어(Codex P1): 라벨 자신은 제외하고, 추출값이 필드명 문자열이면 무효 처리. */
    private static String scrydexField(Document doc, String field) {
        Element label = doc.selectFirst("[data-field='" + field + "']");
        if (label == null || label.parent() == null) return null;
        Element val = null;
        for (Element e : label.parent().select(".text-body-16")) {
            if (!e.equals(label)) { val = e; break; }
        }
        if (val == null) return null;
        String t = val.text().trim();
        if (t.isEmpty() || t.equalsIgnoreCase(field)) return null;  // 라벨명 그대로면 무효
        return t;
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
