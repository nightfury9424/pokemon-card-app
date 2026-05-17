package com.fury.back.domain.price;

import com.fury.back.domain.price.dto.ScrydexHistoryDto;
import com.fury.back.domain.price.dto.ScrydexLivePriceDto;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@Slf4j
@Component
public class ScrydexLiveClient {

    private static final String BASE = "https://scrydex.com/pokemon/cards/_/";
    private static final Duration TIMEOUT = Duration.ofSeconds(15);
    private static final long CACHE_TTL_MS = 2 * 60 * 60 * 1000L; // 2시간
    private static final double JPY_USD_RATE = 150.0; // JPY→USD 변환용 (scrydex JP 페이지는 ¥로 표시)

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(TIMEOUT)
            .followRedirects(HttpClient.Redirect.NORMAL)
            .build();

    private record HtmlCache(String html, long expiresAt) {}
    private record LiveCache(ScrydexLivePriceDto data, long expiresAt) {}

    private final Map<String, HtmlCache>  htmlCache = new ConcurrentHashMap<>();
    private final Map<String, LiveCache>  liveCache = new ConcurrentHashMap<>();

    // ─── HTML fetch (공유 캐시) ───────────────────────────────────

    private String fetchHtml(String ref) {
        HtmlCache cached = htmlCache.get(ref);
        if (cached != null && cached.expiresAt() > System.currentTimeMillis()) {
            return cached.html();
        }
        try {
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(BASE + ref))
                    .timeout(TIMEOUT)
                    .header("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
                    .GET()
                    .build();
            HttpResponse<String> res = http.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() != 200) {
                log.debug("scrydex 응답 {}: {}", res.statusCode(), ref);
                return null;
            }
            String html = res.body();
            htmlCache.put(ref, new HtmlCache(html, System.currentTimeMillis() + CACHE_TTL_MS));
            return html;
        } catch (Exception e) {
            log.warn("scrydex fetch 실패: ref={}, err={}", ref, e.getMessage());
            return null;
        }
    }

    // ─── 실시간 현재가 ─────────────────────────────────────────────

    public Optional<ScrydexLivePriceDto> fetchPrices(String ref, String source) {
        if (ref == null || ref.isBlank() || ref.startsWith("NO_")) return Optional.empty();

        LiveCache cached = liveCache.get(ref);
        if (cached != null && cached.expiresAt() > System.currentTimeMillis()) {
            return Optional.ofNullable(cached.data());
        }

        String html = fetchHtml(ref);
        if (html == null) return Optional.empty();

        ScrydexLivePriceDto dto = parseLive(html, ref, source);
        liveCache.put(ref, new LiveCache(dto, System.currentTimeMillis() + CACHE_TTL_MS));
        return Optional.ofNullable(dto);
    }

    private ScrydexLivePriceDto parseLive(String html, String ref, String source) {
        Double rawNm = parseRawNm(html, "JP".equals(source));
        Map<String, Double> psaPrices = parsePsaLatest(html);

        // Sanity check: RAW가 PSA9의 20% 미만이면 파싱 오류로 간주
        // PSA10은 프로모 카드의 경우 RAW 대비 10배 이상 가능하므로 체크 제외
        if (rawNm != null) {
            Double psa9 = psaPrices.get("9");
            if (psa9 != null && psa9 > 0 && rawNm < psa9 * 0.20) {
                log.warn("[ScrydexLive] RAW sanity 실패 (ref={}, raw={}, psa9={}) → RAW 무효 처리",
                        ref, rawNm, psa9);
                rawNm = null;
            }
        }

        if (rawNm == null && psaPrices.isEmpty()) return null;
        return ScrydexLivePriceDto.builder()
                .rawNm(rawNm)
                .psa10(psaPrices.get("10"))
                .psa9(psaPrices.get("9"))
                .source(source)
                .ref(ref)
                .build();
    }

    // ─── 히스토리 (RAW NM + PSA 10/9) ────────────────────────────

    public Optional<ScrydexHistoryDto> fetchHistory(String ref, String source) {
        if (ref == null || ref.isBlank() || ref.startsWith("NO_")) return Optional.empty();

        String html = fetchHtml(ref);
        if (html == null) return Optional.empty();

        return Optional.ofNullable(parseHistory(html, ref, source));
    }

    private ScrydexHistoryDto parseHistory(String html, String ref, String source) {
        // new Chartkick["LineChart"]("ID", [...], {
        Pattern chartPat = Pattern.compile(
                "new Chartkick\\[\"LineChart\"\\]\\(\"([^\"]+)\",\\s*(\\[.*?\\]),\\s*\\{",
                Pattern.DOTALL);
        Matcher m = chartPat.matcher(html);

        List<ScrydexHistoryDto.PricePoint> rawNm = null;
        List<ScrydexHistoryDto.PricePoint> psa10 = null;
        List<ScrydexHistoryDto.PricePoint> psa9  = null;

        while (m.find()) {
            String chartId = m.group(1);
            String data    = m.group(2);

            if (chartId.contains("_Raw_")) {
                rawNm = parseSeriesFirst(data);
            } else if (chartId.contains("_PSA_")) {
                psa10 = parseSeriesByName(data, "PSA 10");
                psa9  = parseSeriesByName(data, "PSA 9");
            }
        }

        if (rawNm == null && psa10 == null && psa9 == null) return null;

        return ScrydexHistoryDto.builder()
                .rawNm(rawNm)
                .psa10(psa10)
                .psa9(psa9)
                .source(source)
                .ref(ref)
                .build();
    }

    /** 배열 첫 번째 series 파싱 (RAW NM) */
    private List<ScrydexHistoryDto.PricePoint> parseSeriesFirst(String data) {
        // [{"name":"NM","data":[["2026-04-11",30.05],...]}]
        Pattern seriesPat = Pattern.compile("\"data\":\\s*(\\[\\[.*?\\]\\])", Pattern.DOTALL);
        Matcher m = seriesPat.matcher(data);
        if (!m.find()) return null;
        return parsePointArray(m.group(1));
    }

    /** 배열에서 특정 name의 series 파싱 */
    private List<ScrydexHistoryDto.PricePoint> parseSeriesByName(String data, String name) {
        // {"name":"PSA 10","data":[...]}
        String escaped = Pattern.quote(name);
        Pattern seriesPat = Pattern.compile(
                "\"name\":\\s*\"" + escaped + "\"[^}]*?\"data\":\\s*(\\[\\[.*?\\]\\])", Pattern.DOTALL);
        Matcher m = seriesPat.matcher(data);
        if (!m.find()) return null;
        return parsePointArray(m.group(1));
    }

    /** [["2026-04-11",30.05],["2026-04-12",null],...] 파싱 */
    private List<ScrydexHistoryDto.PricePoint> parsePointArray(String arrayStr) {
        Pattern pointPat = Pattern.compile("\\[\"(\\d{4}-\\d{2}-\\d{2})\",\\s*(null|\\d+\\.?\\d*)\\]");
        Matcher m = pointPat.matcher(arrayStr);
        List<ScrydexHistoryDto.PricePoint> points = new ArrayList<>();
        while (m.find()) {
            String date = m.group(1);
            String val  = m.group(2);
            Double price = "null".equals(val) ? null : Double.parseDouble(val);
            points.add(ScrydexHistoryDto.PricePoint.builder().date(date).price(price).build());
        }
        return points.isEmpty() ? null : points;
    }

    // ─── 파싱 유틸 (현재가용) ──────────────────────────────────────

    /** Raw NM 현재가: 차트 마지막 포인트 우선 → 차트 없는 JP만 ¥ 텍스트 파싱 폴백 */
    private Double parseRawNm(String html, boolean isJp) {
        // 1. Chartkick _Raw_ 차트 마지막 non-null 포인트 (EN/JP 공통, 가장 신뢰도 높음)
        Double fromChart = parseRawNmFromChart(html);
        if (fromChart != null) return fromChart;

        // 2. 차트 없는 JP 페이지만 ¥ 텍스트 파싱 폴백
        if (isJp) {
            Pattern jpyPat = Pattern.compile("Near Mint[^¥￥]{0,300}[¥￥]([\\d,]+)", Pattern.DOTALL);
            Matcher m = jpyPat.matcher(html);
            if (m.find()) {
                try {
                    double jpy = Double.parseDouble(m.group(1).replace(",", ""));
                    return jpy / JPY_USD_RATE;
                } catch (NumberFormatException ignored) {}
            }
        }
        return null;
    }

    /** Chartkick _Raw_ 차트에서 마지막 10개 non-null NM 포인트의 중앙값 */
    private Double parseRawNmFromChart(String html) {
        Pattern chartPat = Pattern.compile(
                "new Chartkick\\[\"LineChart\"\\]\\(\"([^\"]+)\",\\s*(\\[.*?\\]),\\s*\\{",
                Pattern.DOTALL);
        Matcher cm = chartPat.matcher(html);
        while (cm.find()) {
            if (!cm.group(1).contains("_Raw_")) continue;
            List<ScrydexHistoryDto.PricePoint> pts = parseSeriesFirst(cm.group(2));
            if (pts == null) continue;
            List<Double> recent = new ArrayList<>();
            for (int i = pts.size() - 1; i >= 0; i--) {
                Double price = pts.get(i).getPrice();
                if (price != null && price > 0) {
                    recent.add(price);
                    if (recent.size() == 10) break;
                }
            }
            if (recent.isEmpty()) continue;
            if (recent.size() < 3) return recent.get(0);
            Collections.sort(recent);
            int mid = recent.size() / 2;
            return recent.size() % 2 == 0
                    ? (recent.get(mid - 1) + recent.get(mid)) / 2.0
                    : recent.get(mid);
        }
        return null;
    }

    private Map<String, Double> parsePsaLatest(String html) {
        Pattern p = Pattern.compile(
                "data-grade=\"(\\d+\\.?\\d*)\"\\s+data-price=\"(\\d+\\.?\\d*)\"\\s+data-currency=\"USD\"\\s+data-sold-at=\"(\\d+)\"");
        Matcher m = p.matcher(html);
        Map<String, long[]>  latestSoldAt = new HashMap<>();
        Map<String, Double>  latestPrice  = new HashMap<>();
        while (m.find()) {
            String grade  = m.group(1);
            double price  = Double.parseDouble(m.group(2));
            long   soldAt = Long.parseLong(m.group(3));
            if (!latestSoldAt.containsKey(grade) || soldAt > latestSoldAt.get(grade)[0]) {
                latestSoldAt.put(grade, new long[]{soldAt});
                latestPrice.put(grade, price);
            }
        }
        Map<String, Double> result = new HashMap<>();
        if (latestPrice.containsKey("10")) result.put("10", latestPrice.get("10"));
        if (latestPrice.containsKey("9"))  result.put("9",  latestPrice.get("9"));
        return result;
    }
}
