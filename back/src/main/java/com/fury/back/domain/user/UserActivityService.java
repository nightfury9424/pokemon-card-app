package com.fury.back.domain.user;

import jakarta.annotation.PreDestroy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;

/**
 * 유저 활동(last_seen) 추적 — DAU(오늘 접속)/접속중 집계용.
 *
 * <p>★핫패스(인증 필터)에서 매 요청마다 호출 → 요청 스레드가 절대 DB/락에 묶이지 않게 설계:
 *  - throttle: in-memory 맵으로 유저당 {@value #THROTTLE_MS}ms 1회만 갱신 대상. 그 외엔 맵 비교(O(1))만.
 *  - DB write 는 단일 데몬 스레드 executor 로 <b>fire-and-forget</b>. 요청 스레드는 비차단 제출만 하고 즉시 반환.
 *  - DB 가 느려 큐가 차면 그냥 버림(DiscardPolicy) — best-effort 지표라 무해, 요청 지연/실패 0.
 *  - 호출측(JwtAuthFilter)도 try-catch 로 한 번 더 감쌈(belt-and-suspenders).
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class UserActivityService {

    private static final long THROTTLE_MS = 60_000L; // 유저당 최소 갱신 간격(1분)

    private final UserRepository userRepository;

    /** userId → 마지막 갱신 epoch millis. 작은 user base 기준 무시 가능(엔트리당 ~50B). */
    private final ConcurrentHashMap<String, Long> lastWrite = new ConcurrentHashMap<>();

    /** 단일 데몬 스레드 + bounded queue(256) + 가득차면 즉시 버림. 요청 스레드는 여기에 비차단 제출만. */
    private final ThreadPoolExecutor writer = new ThreadPoolExecutor(
            1, 1, 0L, TimeUnit.MILLISECONDS,
            new ArrayBlockingQueue<>(256),
            r -> {
                Thread t = new Thread(r, "user-activity");
                t.setDaemon(true);
                return t;
            },
            new ThreadPoolExecutor.DiscardPolicy());

    /** 인증 통과 요청에서 호출. throttle 통과 시 DB 갱신을 백그라운드로 fire-and-forget(요청 스레드 비차단). */
    public void touch(String userId) {
        if (userId == null || userId.isBlank()) return;
        long now = System.currentTimeMillis();
        Long prev = lastWrite.get(userId);
        if (prev != null && now - prev < THROTTLE_MS) return; // throttle — DB·executor 접근 0
        lastWrite.put(userId, now);
        // execute: 큐 여유 있으면 enqueue, 가득차면 DiscardPolicy 로 즉시 버림 → 어느 경우든 비차단.
        writer.execute(() -> {
            try {
                userRepository.touchLastSeen(userId, LocalDateTime.now());
            } catch (Exception e) {
                log.debug("[Activity] last_seen 갱신 실패 userId={}: {}", userId, e.getMessage());
            }
        });
    }

    @PreDestroy
    void shutdown() {
        writer.shutdownNow();
    }
}
