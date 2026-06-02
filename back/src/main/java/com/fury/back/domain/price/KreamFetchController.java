package com.fury.back.domain.price;

import com.fury.back.common.IdGenerator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * 메타몽 KREAM 시세 수집 트리거 — admin 버튼 ↔ 맥북 agent 핸드셰이크.
 *
 * <p><b>왜 맥북 agent?</b> KREAM 봇탐지가 prod 서버(데이터센터) IP 는 막지만 사용자 맥북(가정용)
 * IP 는 통과. 그래서 크롤은 맥북에서 돌아야 함. admin 버튼은 "수집 요청" flag 만 세우고,
 * 맥북 agent 가 polling 하다 flag 보면 맥북 IP 로 크롤 → ingest 로 push.
 *
 * <ul>
 *   <li>POST /api/admin/kream/request  (admin JWT) — 버튼: 수집 요청</li>
 *   <li>GET  /api/admin/kream/status   (admin JWT) — 버튼 옆 진행상태 폴링</li>
 *   <li>GET  /api/kream-agent/claim    (agent 토큰) — agent polling, REQUESTED 면 job 반환</li>
 *   <li>POST /api/kream-agent/ingest   (agent 토큰) — agent 가 크롤한 체결 push</li>
 * </ul>
 */
@Slf4j
@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class KreamFetchController {

    private final KreamFetchState state;
    private final PriceSnapshotRepository priceSnapshotRepository;

    @Value("${app.kream.agent-token:}")
    private String agentToken;
    @Value("${app.kream.card-id:CRD_205C20056CBF48F8B08D}")
    private String cardId;
    @Value("${app.kream.product-id:508949}")
    private String productId;

    // ── admin 버튼 (/api/admin/** → AdminAllowlist 인증) ──
    @PostMapping("/admin/kream/request")
    public Map<String, Object> request() {
        return state.request();
    }

    @GetMapping("/admin/kream/status")
    public Map<String, Object> status() {
        return state.snapshot();
    }

    // ── 맥북 agent (token-gated, /api/kream-agent/** permitAll + 수동 토큰검증) ──
    @GetMapping("/kream-agent/claim")
    public Map<String, Object> claim(
            @RequestHeader(value = "X-Kream-Agent-Token", required = false) String token) {
        requireAgent(token);
        if (!state.claim()) {
            return Map.<String, Object>of("claim", false);
        }
        String after = priceSnapshotRepository
                .findFirstByCardIdAndSourceOrderByTradedAtDesc(cardId, "KREAM")
                .map(s -> s.getTradedAt().toString())
                .orElse("");
        return Map.<String, Object>of(
                "claim", true,
                "cardId", cardId,
                "productId", productId,
                "afterTradedAt", after);
    }

    @PostMapping("/kream-agent/ingest")
    @Transactional
    public Map<String, Object> ingest(
            @RequestHeader(value = "X-Kream-Agent-Token", required = false) String token,
            @RequestBody IngestRequest body) {
        requireAgent(token);
        // agent 가 크롤 실패를 보고한 경우 → status FAILED.
        if (body.error() != null && !body.error().isBlank()) {
            state.fail(body.error());
            return Map.<String, Object>of("ok", false);
        }
        try {
            LocalDateTime maxExisting = priceSnapshotRepository
                    .findFirstByCardIdAndSourceOrderByTradedAtDesc(cardId, "KREAM")
                    .map(PriceSnapshot::getTradedAt)
                    .orElse(null);
            int inserted = 0;
            List<Sale> sales = body.sales() == null ? List.of() : body.sales();
            for (Sale s : sales) {
                LocalDateTime tradedAt = LocalDateTime.parse(s.tradedAt());
                // incremental dedupe — 기존 MAX 이후만 (agent 가 afterTradedAt 으로 이미 필터하지만 이중 가드).
                if (maxExisting != null && !tradedAt.isAfter(maxExisting)) continue;
                String status = s.cardStatus() == null ? "RAW" : s.cardStatus();
                priceSnapshotRepository.save(PriceSnapshot.builder()
                        .priceSnapshotId(IdGenerator.generate())
                        .cardId(cardId)
                        .source("KREAM")
                        .price(s.price())
                        .cardStatus(status)
                        .gradingCompany(s.gradingCompany())
                        .gradeValue(s.gradeValue())
                        .title(s.title())
                        .tradedAt(tradedAt)
                        .rawPrice(BigDecimal.valueOf(s.price()))
                        .rawCurrency("KRW")
                        .collectedAt(LocalDateTime.now())
                        .build());
                inserted++;
            }
            state.complete(inserted);
            log.info("[KreamFetch] agent ingest {}건 적층", inserted);
            return Map.<String, Object>of("inserted", inserted);
        } catch (Exception e) {
            state.fail(e.getMessage());
            log.warn("[KreamFetch] ingest 실패: {}", e.getMessage());
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "ingest 실패");
        }
    }

    private void requireAgent(String token) {
        if (agentToken == null || agentToken.isBlank() || !agentToken.equals(token)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "agent token invalid");
        }
    }

    public record IngestRequest(List<Sale> sales, String error) {}

    /** 맥북 agent 가 크롤한 KREAM 체결 1건. tradedAt 은 ISO LocalDateTime 문자열. */
    public record Sale(String cardStatus, String gradingCompany, String gradeValue,
                       String title, int price, String tradedAt) {}
}
