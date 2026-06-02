package com.fury.back.domain.price;

import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Map;

/**
 * 메타몽 KREAM 시세 수집 트리거 상태 — admin 버튼 ↔ 맥 agent 핸드셰이크.
 *
 * <p>인메모리: flag 수명이 클릭→수집까지 수초~수분이라 영속(테이블) 불필요. prod 재시작 시
 * pending 유실 = 사용자 재클릭으로 무해. 마지막 결과도 재시작 시 리셋(표시용, 비크리티컬).
 */
@Component
public class KreamFetchState {

    public enum Status { IDLE, REQUESTED, RUNNING, DONE, FAILED }

    private Status status = Status.IDLE;
    private Instant requestedAt;
    private Instant updatedAt;
    private int lastCount;
    private String message = "";

    /** admin 버튼 — 진행 중이 아니면 REQUESTED 전이. */
    public synchronized Map<String, Object> request() {
        if (status != Status.REQUESTED && status != Status.RUNNING) {
            status = Status.REQUESTED;
            requestedAt = Instant.now();
            updatedAt = requestedAt;
            message = "수집 요청됨 — 맥 agent 가 가져오는 중";
        }
        return snapshot();
    }

    /** agent claim — REQUESTED 면 RUNNING 으로 전이하고 true. */
    public synchronized boolean claim() {
        if (status == Status.REQUESTED) {
            status = Status.RUNNING;
            updatedAt = Instant.now();
            message = "수집 중";
            return true;
        }
        return false;
    }

    public synchronized void complete(int count) {
        status = Status.DONE;
        lastCount = count;
        updatedAt = Instant.now();
        message = count + "건 반영됨";
    }

    public synchronized void fail(String msg) {
        status = Status.FAILED;
        updatedAt = Instant.now();
        message = (msg == null || msg.isBlank()) ? "수집 실패" : msg;
    }

    public synchronized Map<String, Object> snapshot() {
        return Map.<String, Object>of(
                "status", status.name(),
                "requestedAt", requestedAt == null ? "" : requestedAt.toString(),
                "updatedAt", updatedAt == null ? "" : updatedAt.toString(),
                "lastCount", lastCount,
                "message", message);
    }
}
