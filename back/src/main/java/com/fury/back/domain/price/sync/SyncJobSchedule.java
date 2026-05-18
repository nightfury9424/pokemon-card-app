package com.fury.back.domain.price.sync;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

import java.time.Clock;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.util.Map;

/**
 * Job 스케줄 정의 + due businessDate 계산.
 *
 * Clock은 SyncCatchUpConfig가 Bean으로 제공한다 (테스트에서 fixed Clock 주입 가능).
 */
@Component
@RequiredArgsConstructor
public class SyncJobSchedule {

    public static final ZoneId KST = ZoneId.of("Asia/Seoul");
    public static final int GRACE_MINUTES = 10;
    public static final int MAX_RETRY = 3;
    public static final int STALE_TIMEOUT_MINUTES = 120;

    public static final String JOB_SCRYDEX = "SCRYDEX_DAILY";
    public static final String JOB_REFRESH_KO = "REFRESH_KO_ESTIMATED";

    private final Clock clock;

    private final Map<String, LocalTime> scheduleMap = Map.of(
        JOB_SCRYDEX,    LocalTime.of(21, 0),
        JOB_REFRESH_KO, LocalTime.of(23, 45)
    );

    public LocalTime scheduledTime(String jobName) {
        LocalTime t = scheduleMap.get(jobName);
        if (t == null) throw new IllegalArgumentException("Unknown jobName: " + jobName);
        return t;
    }

    /**
     * due businessDate — "지금 시각 기준으로 catch-up 대상이 되는 가장 최근 due 날짜".
     *
     * now < scheduled + grace(10min)이면 어제 날짜, 아니면 오늘 날짜.
     * Codex [2] 권고 — Clock + ZoneId 명시로 테스트 가능.
     */
    public LocalDate dueBusinessDate(String jobName) {
        ZonedDateTime now = ZonedDateTime.now(clock).withZoneSameInstant(KST);
        LocalTime cutoff = scheduledTime(jobName).plusMinutes(GRACE_MINUTES);
        return now.toLocalTime().isBefore(cutoff)
            ? now.toLocalDate().minusDays(1)
            : now.toLocalDate();
    }

    /** bizDate의 scheduled time을 KST OffsetDateTime으로 변환 (price_sync_runs.scheduled_at 적재용). */
    public OffsetDateTime scheduledAt(String jobName, LocalDate businessDate) {
        return businessDate.atTime(scheduledTime(jobName)).atZone(KST).toOffsetDateTime();
    }
}
