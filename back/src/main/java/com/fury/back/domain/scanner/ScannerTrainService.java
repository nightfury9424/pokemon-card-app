package com.fury.back.domain.scanner;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 스캔 모델 재학습 오케스트레이션 (docs/IMAGE_DATA_STRATEGY.md FF1) — 메타몽식 맥북 agent.
 * 무중단: 학습 중 서버는 OLD 인덱스 서빙. TRAINED 후 명시적 deploy 시에만 prod 스캐너가 원자 스왑.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ScannerTrainService {

    private final ScanTrainJobRepository jobRepo;
    private final ScanCaptureRepository captureRepo;

    @Value("${scanner.base-url:http://localhost:8082}")
    private String scannerBaseUrl;

    private static final int SAMPLE_LIMIT = 5000;

    // ── admin ──

    /** 학습하기 — REQUESTED job 생성. 진행 중 job 있으면 거부(중복 방지). */
    @Transactional
    public ScanTrainJob requestTrain(String adminUserId) {
        jobRepo.findFirstByOrderByRequestedAtDesc().ifPresent(j -> {
            if (j.isActive()) {
                throw new ResponseStatusException(HttpStatus.CONFLICT,
                        "이미 진행 중인 학습 job 이 있습니다 (" + j.getStatus() + ").");
            }
        });
        return jobRepo.save(ScanTrainJob.request(adminUserId));
    }

    /** 업데이트하기 — TRAINED job 을 prod 스캐너에 배포(원자 스왑). TRAINED 아니면 거부. */
    @Transactional
    public Map<String, Object> deploy() {
        ScanTrainJob job = jobRepo.findFirstByOrderByRequestedAtDesc()
                .filter(j -> j.getStatus() == ScanTrainJob.Status.TRAINED)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.CONFLICT,
                        "배포 가능한 TRAINED job 이 없습니다."));
        job.markDeploying();
        jobRepo.saveAndFlush(job);
        try {
            // prod 스캐너에 staging 인덱스 reload 요청 (원자 스왑). 그 전까지 서버는 OLD 서빙.
            RestTemplate rt = restTemplate();
            rt.postForEntity(scannerBaseUrl + "/admin/reload-index?key={k}", null, Map.class,
                    job.getStagedIndexKey());
            int marked = captureRepo.markIndexedBefore(job.getTrainedAt());
            job.markDeployed();
            jobRepo.save(job);
            log.info("[ScanTrain] deployed job={} markedIndexed={}", job.getJobId(), marked);
            return Map.of("status", "DEPLOYED", "markedIndexed", marked);
        } catch (Exception e) {
            job.markFailed("deploy 실패: " + e.getMessage());
            jobRepo.save(job);
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR,
                    "스캐너 인덱스 reload 실패: " + e.getMessage());
        }
    }

    /** 상태 — admin UI 버튼 게이팅 (canTrain / canDeploy). */
    @Transactional(readOnly = true)
    public Map<String, Object> status() {
        ScanTrainJob job = jobRepo.findFirstByOrderByRequestedAtDesc().orElse(null);
        Map<String, Object> m = new HashMap<>();
        m.put("status", job == null ? "NONE" : job.getStatus().name());
        m.put("jobId", job == null ? null : job.getJobId());
        m.put("sampleCount", job == null ? null : job.getSampleCount());
        m.put("message", job == null ? null : job.getMessage());
        m.put("unindexedCaptures", captureRepo.countByFaissIndexedFalseAndDeletedAtIsNull());
        m.put("canTrain", job == null || !job.isActive());
        m.put("canDeploy", job != null && job.getStatus() == ScanTrainJob.Status.TRAINED);
        return m;
    }

    // ── 맥북 agent (token-gated) ──

    /** agent claim — REQUESTED job 을 TRAINING 으로 전이하고 반환. 없으면 empty. */
    @Transactional
    public Optional<ScanTrainJob> claim() {
        List<ScanTrainJob> requested = jobRepo
                .findByStatusOrderByRequestedAtAsc(ScanTrainJob.Status.REQUESTED);
        if (requested.isEmpty()) return Optional.empty();
        ScanTrainJob job = requested.get(0);
        job.markTraining();
        return Optional.of(job);
    }

    /** agent 가 학습에 쓸 미인덱스 샘플 목록 (cardId + S3 key). agent 가 S3 에서 다운로드. */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> unindexedSamples() {
        return captureRepo.findUnindexed(PageRequest.of(0, SAMPLE_LIMIT)).stream()
                .map(s -> Map.<String, Object>of(
                        "captureId", s.getCaptureId(),
                        "cardId", s.getCardId(),
                        "s3Key", s.getS3Key()))
                .toList();
    }

    /** agent 가 학습 완료 보고 — staging 인덱스 key + 샘플수. 실패 시 error. */
    @Transactional
    public void reportTrained(String jobId, String stagedKey, Integer sampleCount, String error) {
        ScanTrainJob job = jobRepo.findById(jobId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "job 없음: " + jobId));
        if (error != null && !error.isBlank()) {
            job.markFailed(error);
            return;
        }
        job.markTrained(stagedKey, sampleCount);
    }

    private RestTemplate restTemplate() {
        SimpleClientHttpRequestFactory f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(5_000);
        f.setReadTimeout(120_000); // 인덱스 다운로드+reload 여유
        return new RestTemplate(f);
    }
}
