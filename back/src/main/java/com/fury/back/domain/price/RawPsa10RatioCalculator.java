package com.fury.back.domain.price;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * PSA10 → RAW 환산 비율 계산기.
 *
 * 하루 1회 cron으로 호출. (source, rarity)별 median(RAW/PSA10) 계산해
 * raw_psa10_ratios 테이블 UPSERT. PSA10만 있는 카드의 RAW 추정에 사용.
 *
 * <h3>알고리즘</h3>
 * <ol>
 *   <li>기본 14일 윈도우로 paired RAW + PSA10 카드 추출 (raw &lt; psa10 + ≥ 1000원)</li>
 *   <li>(source, rarity) 그룹화 → IQR 기반 outlier 제거 → median/p25/p75 계산</li>
 *   <li>샘플 &lt; 30인 (source, rarity)는 30일 윈도우로 재시도</li>
 *   <li>그래도 부족한 경우 별도 처리 (현재는 skip — 호출자가 fallback 책임)</li>
 * </ol>
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class RawPsa10RatioCalculator {

    private static final int DEFAULT_WINDOW_DAYS = 14;
    private static final int EXTENDED_WINDOW_DAYS = 30;
    private static final int MIN_SAMPLES = 30;

    private final RawPsa10RatioRepository repository;

    @Transactional
    public Result recalculate() {
        log.info("[RawPsa10Ratio] 비율 재계산 시작");
        Map<GroupKey, List<BigDecimal>> grouped = collect(DEFAULT_WINDOW_DAYS);

        // 14일 윈도우 결과 우선. 샘플 부족 그룹은 30일 윈도우로 보강.
        Map<GroupKey, Integer> windowByGroup = new HashMap<>();
        for (GroupKey k : grouped.keySet()) windowByGroup.put(k, DEFAULT_WINDOW_DAYS);

        Map<GroupKey, List<BigDecimal>> extended = null;
        for (Map.Entry<GroupKey, List<BigDecimal>> e : grouped.entrySet()) {
            if (e.getValue().size() < MIN_SAMPLES) {
                if (extended == null) extended = collect(EXTENDED_WINDOW_DAYS);
                List<BigDecimal> ext = extended.get(e.getKey());
                if (ext != null && ext.size() > e.getValue().size()) {
                    e.setValue(ext);
                    windowByGroup.put(e.getKey(), EXTENDED_WINDOW_DAYS);
                }
            }
        }

        // 30일 윈도우에만 있는 그룹도 추가
        if (extended != null) {
            for (Map.Entry<GroupKey, List<BigDecimal>> e : extended.entrySet()) {
                if (!grouped.containsKey(e.getKey())) {
                    grouped.put(e.getKey(), e.getValue());
                    windowByGroup.put(e.getKey(), EXTENDED_WINDOW_DAYS);
                }
            }
        }

        int saved = 0;
        for (Map.Entry<GroupKey, List<BigDecimal>> e : grouped.entrySet()) {
            List<BigDecimal> ratios = e.getValue();
            if (ratios.isEmpty()) continue;
            List<BigDecimal> trimmed = trimIqr(ratios);
            if (trimmed.size() < 5) continue;  // IQR 후 너무 적으면 신뢰성 ↓
            BigDecimal median = percentile(trimmed, 0.5);
            BigDecimal p25 = percentile(trimmed, 0.25);
            BigDecimal p75 = percentile(trimmed, 0.75);
            RawPsa10Ratio entity = RawPsa10Ratio.builder()
                    .source(e.getKey().source())
                    .rarityCode(e.getKey().rarity())
                    .windowDays(windowByGroup.get(e.getKey()))
                    .sampleCount(trimmed.size())
                    .ratioMedian(median)
                    .ratioP25(p25)
                    .ratioP75(p75)
                    .computedAt(LocalDateTime.now())
                    .build();
            repository.save(entity);
            saved++;
        }
        log.info("[RawPsa10Ratio] 완료 — {}개 (source, rarity) 비율 저장", saved);
        return new Result(saved, grouped.size());
    }

    /** native query 결과(source, rarity, ratio)를 (source, rarity)별 ratio 리스트로. */
    private Map<GroupKey, List<BigDecimal>> collect(int windowDays) {
        List<Object[]> rows = repository.findPairsForRatio(windowDays);
        Map<GroupKey, List<BigDecimal>> map = new HashMap<>();
        for (Object[] row : rows) {
            if (row[0] == null || row[1] == null || row[2] == null) continue;
            String source = (String) row[0];
            String rarity = (String) row[1];
            BigDecimal ratio = (BigDecimal) row[2];
            map.computeIfAbsent(new GroupKey(source, rarity), k -> new ArrayList<>())
               .add(ratio);
        }
        return map;
    }

    /**
     * IQR 기반 outlier trimming. [Q1 - 1.5×IQR, Q3 + 1.5×IQR] 범위만 유지.
     * (raw/psa10 비율은 0~1 범위라 아래쪽도 비정상 가능.)
     */
    static List<BigDecimal> trimIqr(List<BigDecimal> values) {
        if (values.size() < 4) return values;
        List<BigDecimal> sorted = new ArrayList<>(values);
        sorted.sort(Comparator.naturalOrder());
        BigDecimal q1 = percentile(sorted, 0.25);
        BigDecimal q3 = percentile(sorted, 0.75);
        BigDecimal iqr = q3.subtract(q1);
        BigDecimal lower = q1.subtract(iqr.multiply(BigDecimal.valueOf(1.5)));
        BigDecimal upper = q3.add(iqr.multiply(BigDecimal.valueOf(1.5)));
        List<BigDecimal> out = new ArrayList<>(sorted.size());
        for (BigDecimal v : sorted) {
            if (v.compareTo(lower) >= 0 && v.compareTo(upper) <= 0) out.add(v);
        }
        return out;
    }

    /** 보간 percentile. values는 정렬된 상태로 가정해도 되도록 내부 sort. */
    static BigDecimal percentile(List<BigDecimal> values, double pct) {
        List<BigDecimal> sorted = new ArrayList<>(values);
        sorted.sort(Comparator.naturalOrder());
        if (sorted.isEmpty()) return BigDecimal.ZERO;
        if (sorted.size() == 1) return sorted.get(0).setScale(5, RoundingMode.HALF_UP);
        double idx = pct * (sorted.size() - 1);
        int lo = (int) Math.floor(idx);
        int hi = (int) Math.ceil(idx);
        if (lo == hi) return sorted.get(lo).setScale(5, RoundingMode.HALF_UP);
        BigDecimal frac = BigDecimal.valueOf(idx - lo);
        BigDecimal a = sorted.get(lo);
        BigDecimal b = sorted.get(hi);
        return a.add(b.subtract(a).multiply(frac)).setScale(5, RoundingMode.HALF_UP);
    }

    /**
     * 외부 호출 — PSA10 → 추정 RAW 환산. ratio 없으면 Optional.empty.
     * `derived = psa10 × ratioMedian`, 정수 원 단위로 반올림.
     */
    public Optional<Integer> deriveRawFromPsa10(String source, String rarity, int psa10Price) {
        if (psa10Price <= 0) return Optional.empty();
        return repository.findBySourceAndRarityCode(source, rarity)
                .map(r -> BigDecimal.valueOf(psa10Price)
                        .multiply(r.getRatioMedian())
                        .setScale(0, RoundingMode.HALF_UP)
                        .intValueExact());
    }

    private record GroupKey(String source, String rarity) {}

    public record Result(int savedGroups, int totalGroups) {}
}
