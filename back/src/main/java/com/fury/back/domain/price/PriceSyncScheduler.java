package com.fury.back.domain.price;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.List;

@Slf4j
@Component
@RequiredArgsConstructor
public class PriceSyncScheduler {

    @Value("${app.python.system}")
    private String python3;

    @Value("${app.python.venv-kream}")
    private String venvKreamPython;

    @Value("${app.python.scripts-dir}")
    private String pythonScriptsDir;

    private final GlobalPriceService globalPriceService;
    private final CoefficientCache   coefficientCache;
    private final com.fury.back.domain.notification.NotificationService notificationService;
    private final RawPsa10RatioCalculator rawPsa10RatioCalculator;

    // Option B-lite (2026-05-18): Java recalculateEnJpRatios() 자동 cron 비활성화.
    // RARITY coef 단일 진실원 = Python recalc.py --mode rarity (주1회 월요일 03:00).
    // 비상시 운영에서 true로 toggle 가능 (메서드 자체는 유지).
    @Value("${price.rarity-java-cron.enabled:false}")
    private boolean rarityJavaCronEnabled;

    /** scripts-dir 기준으로 python 스크립트 절대경로 조립. */
    private String script(String name) {
        return pythonScriptsDir + "/" + name;
    }

    /**
     * 매일 21:00: scrydex 해외 시세 수집 (SCRYDEX_EN / SCRYDEX_JP)
     * ~30분 소요. 완료 후 price_scrydex.py가 오늘자 KO_ESTIMATED 1차 재계산 자동 호출.
     */
    @Scheduled(cron = "0 0 21 * * *")
    public void syncGlobalPrices() {
        log.info("[PriceSync] ① scrydex 해외 시세 수집 시작");
        runPython(script("price_scrydex.py"));
        log.info("[PriceSync] ① scrydex 해외 시세 수집 완료");
    }

    /**
     * 매일 21:30: 프로모 카드 eBay 가격 수집 (scrydex 수집과 겹치지 않도록 30분 후)
     */
    @Scheduled(cron = "0 30 21 * * *")
    public void syncPromoPrice() {
        log.info("[PriceSync] 프로모 eBay 가격 수집 시작");
        runPython(script("price_promo_ebay.py"));
        log.info("[PriceSync] 프로모 eBay 가격 수집 완료");
    }

    /**
     * 매일 21:45: KREAM 메타몽 Pokemon Town 2025 프로모 체결가 수집.
     * 12개 등급 옵션(Ungraded/PSA10/9/8 + BRG 10/9/8.5/8 영문·한글) 분리 적층.
     * curl_cffi 의존성 때문에 별도 venv python 사용.
     * exit code 2 = 토큰 만료, 3 = 차단, 4 = 응답 구조 변경 — 운영 알림 대상.
     */
    @Scheduled(cron = "0 45 21 * * *")
    public void syncKreamDittoPromo() {
        log.info("[PriceSync] KREAM 메타몽 프로모 시세 수집 시작");
        runWithPython(venvKreamPython, script("kream_ditto.py"));
        log.info("[PriceSync] KREAM 메타몽 프로모 시세 수집 완료");
    }

    /**
     * 매일 22:00: 네이버 카페 낙찰가 수집 (계수 재계산용)
     */
    @Scheduled(cron = "0 0 22 * * *")
    public void syncNaverCafeAuctions() {
        log.info("[PriceSync] ② 네이버 카페 낙찰가 수집 시작");
        runPython(script("price_naver_cafe.py"), "--days", "30");
        log.info("[PriceSync] ② 네이버 카페 낙찰가 수집 완료");
    }

    /**
     * 매일 23:00: GLOBAL 계수만 매일 재계산 (--mode global).
     * 검수 substrate(NAVER_CAFE_OLD + DAANGN.VALID + NAVER_CAFE.VALID) 기반 raw global 산출 후
     * 최근 7개 RAW observation median을 ko_coef_jp_GLOBAL / ko_coef_en_GLOBAL에 저장 (Java 무변경).
     * RARITY 계수는 별도 월요일 03:00 cron에서 주1회 재계산.
     * (docs/PRICE_POLICY_2026_05_16.md §9 운영 cron 참조)
     */
    @Scheduled(cron = "0 0 23 * * *")
    public void recalcGlobalDaily() {
        log.info("[PriceSync] ③ GLOBAL 매일 재계산 시작 (--mode global)");
        runPython(script("recalc_coefficients.py"), "--mode", "global");
        log.info("[PriceSync] ③ GLOBAL 매일 재계산 완료");
    }

    /**
     * 매주 월요일 03:00: RARITY 주1회 재계산 (--mode rarity) + CARD coef 보강.
     * 사용자가 03:00 전까지 PENDING_REVIEW 데이터 검수를 마쳐야 substrate에 반영됨.
     * 03:00 전 미검수 PENDING은 해당 주 substrate에서 제외.
     * (docs/PRICE_POLICY_2026_05_16.md §2 사용자 검수 + §7 RARITY 정책 참조)
     */
    @Scheduled(cron = "0 0 3 * * MON")
    public void recalcRarityAndCardWeekly() {
        log.info("[PriceSync] 월요일 03:00 RARITY 재계산 시작 (--mode rarity)");
        runPython(script("recalc_coefficients.py"), "--mode", "rarity");
        log.info("[PriceSync] 월요일 03:00 RARITY 완료 → CARD coef 보강 시작");
        runPython(script("calc_ko_coefficients_v1.py"));
        log.info("[PriceSync] 월요일 03:00 RARITY + CARD 통합 작업 완료");
    }

    /**
     * 매일 23:15: 글로벌 계수 재계산 (CoefficientCache 갱신)
     */
    @Scheduled(cron = "0 15 23 * * *")
    public void recalculateCoefficient() {
        log.info("[PriceSync] ④ 글로벌 계수 재계산 시작");
        try {
            var result = globalPriceService.recalculateCoefficient();
            coefficientCache.update(result);
            log.info("[PriceSync] ④ 계수 재계산 완료: coefficient={}, sample={}장",
                    result.getCoefficient(), result.getSampleSize());
        } catch (Exception e) {
            log.error("[PriceSync] ④ 계수 재계산 실패: {}", e.getMessage(), e);
        }
    }

    /**
     * 매일 23:30: EN/JP 가격 비율 재계산.
     *
     * Option B-lite (2026-05-18): 기본 비활성화.
     * - 이유: Java recalculateEnJpRatios()와 Python recalc.py --mode rarity가 같은 RARITY coef를
     *   다른 로직(window, 1.12 곱, IQR fence, EXCLUDE_RARITIES)으로 갱신하여 충돌 발생.
     * - 결정: RARITY coef 단일 진실원 = Python recalc.py --mode rarity (주1회 월요일 03:00).
     * - 메서드 자체는 유지 (비상시 price.rarity-java-cron.enabled=true로 toggle).
     */
    @Scheduled(cron = "0 30 23 * * *")
    public void recalculateEnJpRatios() {
        if (!rarityJavaCronEnabled) {
            log.info("[PriceSync] ⑤ Java RARITY cron disabled. Python recalc.py is source of truth.");
            return;
        }
        log.info("[PriceSync] ⑤ EN/JP 가격 비율 재계산 시작");
        try {
            globalPriceService.recalculateEnJpRatios();
            log.info("[PriceSync] ⑤ EN/JP 가격 비율 재계산 완료");
        } catch (Exception e) {
            log.error("[PriceSync] ⑤ EN/JP 가격 비율 재계산 실패: {}", e.getMessage(), e);
        }
    }

    /**
     * 매일 23:45: KO_ESTIMATED 최종 재계산
     * 계수 갱신(23:00~23:30) 완료 후 실행 — 자정 전 최신 계수 반영된 KO 예상가 확정.
     */
    @Scheduled(cron = "0 45 23 * * *")
    public void refreshKoEstimates() {
        log.info("[PriceSync] ⑥ KO_ESTIMATED 최종 재계산 시작");
        try {
            globalPriceService.refreshKoEstimatesFromSnapshots();
            log.info("[PriceSync] ⑥ KO_ESTIMATED 최종 재계산 완료");
        } catch (Exception e) {
            log.error("[PriceSync] ⑥ KO_ESTIMATED 최종 재계산 실패: {}", e.getMessage(), e);
        }
    }

    /**
     * 매일 23:55: RAW/PSA10 비율 재계산
     * KO_ESTIMATED 흐름 끝나고 마지막. (source, rarity)별 median 갱신.
     * PSA10만 있는 카드의 RAW 추정(다음날 KO 흐름) 데이터.
     */
    @Scheduled(cron = "0 55 23 * * *")
    public void recalculateRawPsa10Ratios() {
        log.info("[PriceSync] ⑦ RAW/PSA10 비율 재계산 시작");
        try {
            var result = rawPsa10RatioCalculator.recalculate();
            log.info("[PriceSync] ⑦ RAW/PSA10 비율 재계산 완료 — {}/{} 그룹 저장",
                    result.savedGroups(), result.totalGroups());
        } catch (Exception e) {
            log.error("[PriceSync] ⑦ RAW/PSA10 비율 재계산 실패: {}", e.getMessage(), e);
        }
    }

    private void runPython(String scriptPath, String... extraArgs) {
        runWithPython(python3, scriptPath, extraArgs);
    }

    private void runWithPython(String pythonPath, String scriptPath, String... extraArgs) {
        String scriptName = scriptPath.substring(scriptPath.lastIndexOf('/') + 1);
        StringBuilder tail = new StringBuilder();  // 마지막 출력 일부 보존 (알림 body)
        try {
            List<String> cmd = new ArrayList<>();
            cmd.add(pythonPath);
            cmd.add(scriptPath);
            for (String arg : extraArgs) cmd.add(arg);

            ProcessBuilder pb = new ProcessBuilder(cmd);
            // Phase 1-1 fix: cwd = script parent. default cwd=/app이면 script가 같은 디렉토리
            // config.py를 import 못 하고 ModuleNotFoundError (cron 자동 실행 시 silent fail).
            java.io.File scriptDir = new java.io.File(scriptPath).getParentFile();
            if (scriptDir != null && scriptDir.isDirectory()) {
                pb.directory(scriptDir);
            }
            pb.redirectErrorStream(true);
            Process process = pb.start();

            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    log.info("[scraper] {}", line);
                    tail.append(line).append('\n');
                    if (tail.length() > 4000) tail.delete(0, tail.length() - 2000);
                }
            }

            int exitCode = process.waitFor();
            if (exitCode != 0) {
                log.warn("[PriceSync] 스크래퍼 종료 코드: {} ({})", exitCode, scriptPath);
                try {
                    notificationService.notifyOpsFailure(scriptName, exitCode, tail.toString());
                } catch (Exception nx) {
                    log.error("[PriceSync] 운영 알림 생성 실패", nx);
                }
            }
        } catch (Exception e) {
            log.error("[PriceSync] 스크래퍼 실행 실패 ({}): {}", scriptPath, e.getMessage());
            try {
                notificationService.notifyOpsFailure(scriptName, -1, "실행 자체 실패: " + e.getMessage());
            } catch (Exception nx) {
                log.error("[PriceSync] 운영 알림 생성 실패", nx);
            }
        }
    }
}
