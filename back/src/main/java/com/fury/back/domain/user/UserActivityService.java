package com.fury.back.domain.user;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 유저 활동(last_seen) 추적 — DAU(오늘 접속)/접속중 집계용.
 *
 * <p>★핫패스(인증 필터)에서 매 요청마다 호출되므로 서버 부하 최소화가 핵심:
 *  - in-memory throttle 맵으로 유저당 {@value #THROTTLE_MS}ms 에 1회만 DB write.
 *  - 그 외 호출은 맵 비교(O(1))만 하고 즉시 반환 → DB 접근 0.
 *  - touch 는 best-effort: 실패해도 호출측에서 삼켜 요청에 영향 없음.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class UserActivityService {

    private static final long THROTTLE_MS = 60_000L; // 유저당 최소 갱신 간격(1분)

    private final UserRepository userRepository;

    /** userId → 마지막 DB write epoch millis. 작은 user base 기준 무시 가능한 메모리(엔트리당 ~50B). */
    private final ConcurrentHashMap<String, Long> lastWrite = new ConcurrentHashMap<>();

    /** 인증 통과한 요청에서 호출. throttle 통과 시에만 last_seen 갱신. */
    public void touch(String userId) {
        if (userId == null || userId.isBlank()) return;
        long now = System.currentTimeMillis();
        Long prev = lastWrite.get(userId);
        if (prev != null && now - prev < THROTTLE_MS) return; // throttle — DB 접근 없음
        // 동시성: 먼저 맵을 갱신해 중복 write 최소화(드문 race 로 2회 써도 무해).
        lastWrite.put(userId, now);
        userRepository.touchLastSeen(userId, LocalDateTime.now());
    }
}
