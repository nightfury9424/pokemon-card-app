package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

/**
 * 카드 상세 호가창 API. 2026-05-18 신설.
 *
 * <ul>
 *   <li>GET /api/cards/{cardId}/hoga — 매도 5 / 매수 5</li>
 *   <li>GET /api/cards/{cardId}/hoga/{price} — 가격별 등록자 리스트</li>
 * </ul>
 *
 * <p>status 필터: RAW / PSA10 / BRG (1차). CGC/BGS 미지원.
 */
@RestController
@RequestMapping("/api/cards")
@RequiredArgsConstructor
public class HogaController {

    private static final int DEFAULT_LIMIT = 5;
    private static final int MAX_LIMIT = 20;

    private final HogaService hogaService;

    @GetMapping("/{cardId}/hoga")
    public HogaBoardResponse getBoard(
            @PathVariable String cardId,
            @RequestParam(defaultValue = "RAW") String status,
            @RequestParam(defaultValue = "5") int limit) {
        HogaStatus parsed = parseStatus(status);
        int bound = Math.max(1, Math.min(limit, MAX_LIMIT));
        return hogaService.getBoard(cardId, parsed, bound == 0 ? DEFAULT_LIMIT : bound);
    }

    @GetMapping("/{cardId}/hoga/{price}")
    public HogaListingsResponse getListings(
            @PathVariable String cardId,
            @PathVariable long price,
            @RequestParam(defaultValue = "RAW") String status,
            @RequestParam String side) {
        HogaStatus parsedStatus = parseStatus(status);
        HogaSide parsedSide = parseSide(side);
        if (price <= 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "price must be positive");
        }
        return hogaService.getListingsAtPrice(cardId, parsedStatus, parsedSide, price);
    }

    private HogaStatus parseStatus(String raw) {
        if (raw == null) return HogaStatus.RAW;
        try {
            return HogaStatus.valueOf(raw.trim().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "unsupported status: " + raw + " (allowed: RAW, PSA10, BRG)");
        }
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
