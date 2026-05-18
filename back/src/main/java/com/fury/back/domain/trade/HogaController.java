package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.util.Set;

/**
 * 카드 상세 호가창 API. 2026-05-18 신설.
 *
 * <ul>
 *   <li>GET /api/cards/{cardId}/hoga?status=RAW</li>
 *   <li>GET /api/cards/{cardId}/hoga?status=PSA&grade=10</li>
 *   <li>GET /api/cards/{cardId}/hoga/{price}?status=PSA&grade=10&side=ASK</li>
 * </ul>
 *
 * <p>1단 status: RAW / PSA / BRG. PSA/BRG는 2단 grade(10|9) 필수.
 * <p>CGC/BGS 미지원.
 */
@RestController
@RequestMapping("/api/cards")
@RequiredArgsConstructor
public class HogaController {

    private static final int DEFAULT_LIMIT = 5;
    private static final int MAX_LIMIT = 20;
    private static final Set<String> ALLOWED_GRADES = Set.of("10", "9");

    private final HogaService hogaService;

    @GetMapping("/{cardId}/hoga")
    public HogaBoardResponse getBoard(
            @PathVariable String cardId,
            @RequestParam(defaultValue = "RAW") String status,
            @RequestParam(required = false) String grade,
            @RequestParam(defaultValue = "5") int limit) {
        HogaStatus parsed = parseStatus(status);
        String parsedGrade = parseGrade(parsed, grade);
        int bound = Math.max(1, Math.min(limit, MAX_LIMIT));
        return hogaService.getBoard(cardId, parsed, parsedGrade, bound);
    }

    @GetMapping("/{cardId}/hoga/{price}")
    public HogaListingsResponse getListings(
            @PathVariable String cardId,
            @PathVariable long price,
            @RequestParam(defaultValue = "RAW") String status,
            @RequestParam(required = false) String grade,
            @RequestParam String side) {
        HogaStatus parsedStatus = parseStatus(status);
        String parsedGrade = parseGrade(parsedStatus, grade);
        HogaSide parsedSide = parseSide(side);
        if (price <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "price must be positive");
        }
        return hogaService.getListingsAtPrice(cardId, parsedStatus, parsedGrade, parsedSide, price);
    }

    private HogaStatus parseStatus(String raw) {
        if (raw == null) return HogaStatus.RAW;
        try {
            return HogaStatus.valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "unsupported status: " + raw + " (allowed: RAW, PSA, BRG)");
        }
    }

    /** PSA/BRG는 grade(10|9) 필수. RAW는 무시. */
    private String parseGrade(HogaStatus status, String raw) {
        if (!status.requiresGrade()) return null;
        if (raw == null || raw.isBlank()) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "grade required for " + status + " (allowed: 10, 9)");
        }
        String g = raw.trim();
        if (!ALLOWED_GRADES.contains(g)) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "unsupported grade: " + raw + " (allowed: 10, 9)");
        }
        return g;
    }

    private HogaSide parseSide(String raw) {
        if (raw == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "side required (ASK or BID)");
        }
        try {
            return HogaSide.valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST, "side must be ASK or BID");
        }
    }
}
