package com.fury.back.domain.scanner;

import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

/**
 * 스캔 모델 재학습 — admin 버튼(학습하기/업데이트하기) + 맥북 agent (메타몽 KreamFetchController 패턴).
 * admin = /api/admin/scanner/** (AdminAllowlist 인증). agent = /api/scanner-agent/** (permitAll + 토큰).
 */
@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class ScannerTrainController {

    private final ScannerTrainService service;

    @Value("${app.scanner.agent-token:}")
    private String agentToken;

    // ── admin 버튼 ──
    /** 학습하기 — REQUESTED job 생성 (맥 agent 가 폴링해 가져감). */
    @PostMapping("/admin/scanner/train")
    public Map<String, Object> train(@AuthenticationPrincipal String userId) {
        ScanTrainJob job = service.requestTrain(userId);
        return Map.of("jobId", job.getJobId(), "status", job.getStatus().name());
    }

    /** 업데이트하기 — TRAINED 인덱스를 prod 스캐너에 배포(원자 스왑). TRAINED 일 때만. */
    @PostMapping("/admin/scanner/deploy")
    public Map<String, Object> deploy() {
        return service.deploy();
    }

    /** 상태 — admin UI 버튼 게이팅 (canTrain / canDeploy). */
    @GetMapping("/admin/scanner/train-status")
    public Map<String, Object> trainStatus() {
        return service.status();
    }

    /** 복구 — 막힌 job(DEPLOYING stuck 등)을 FAILED 처리해 다음 학습 가능하게. */
    @PostMapping("/admin/scanner/reset")
    public Map<String, Object> reset() {
        return service.reset();
    }

    // ── 맥북 agent (token-gated) ──
    @GetMapping("/scanner-agent/claim")
    public Map<String, Object> claim(
            @RequestHeader(value = "X-Scanner-Agent-Token", required = false) String token) {
        requireAgent(token);
        return service.claim()
                .map(j -> Map.<String, Object>of("claim", true, "jobId", j.getJobId()))
                .orElse(Map.of("claim", false));
    }

    @GetMapping("/scanner-agent/samples")
    public Map<String, Object> samples(
            @RequestHeader(value = "X-Scanner-Agent-Token", required = false) String token) {
        requireAgent(token);
        List<Map<String, Object>> samples = service.unindexedSamples();
        return Map.of("count", samples.size(), "samples", samples);
    }

    @PostMapping("/scanner-agent/trained")
    public Map<String, Object> trained(
            @RequestHeader(value = "X-Scanner-Agent-Token", required = false) String token,
            @RequestBody TrainedRequest body) {
        requireAgent(token);
        service.reportTrained(body.jobId(), body.stagedIndexKey(), body.sampleCount(), body.error());
        return Map.of("ok", true);
    }

    private void requireAgent(String token) {
        if (agentToken == null || agentToken.isBlank() || !agentToken.equals(token)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "scanner agent token invalid");
        }
    }

    public record TrainedRequest(String jobId, String stagedIndexKey, Integer sampleCount, String error) {}
}
