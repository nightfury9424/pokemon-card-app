package com.fury.back.domain.price;

import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.io.BufferedReader;
import java.io.InputStreamReader;

@Slf4j
@Component
public class PriceSyncScheduler {

    private static final String SCRAPER_PATH = "/tmp/scrydex_scraper.py";

    /**
     * 매일 새벽 3시 실행
     * - scrydex_scraper.py: JP/EN 해외 시세 + eBay 실거래가 수집
     */
    @Scheduled(cron = "0 0 3 * * *")
    public void syncGlobalPrices() {
        log.info("[PriceSync] 해외 시세 동기화 시작");
        runPython(SCRAPER_PATH);
        log.info("[PriceSync] 완료");
    }

    private void runPython(String scriptPath) {
        try {
            ProcessBuilder pb = new ProcessBuilder("python3", scriptPath, "--incremental");
            pb.redirectErrorStream(true);
            Process process = pb.start();

            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    log.info("[scraper] {}", line);
                }
            }

            int exitCode = process.waitFor();
            if (exitCode != 0) {
                log.warn("[PriceSync] 스크래퍼 종료 코드: {}", exitCode);
            }
        } catch (Exception e) {
            log.error("[PriceSync] 스크래퍼 실행 실패: {}", e.getMessage());
        }
    }
}
