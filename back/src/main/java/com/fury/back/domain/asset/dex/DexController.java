package com.fury.back.domain.asset.dex;

import com.fury.back.common.ReturnData;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

/**
 * 2026-05-29 Phase B — 도감 (Pokédex 컬렉션) endpoint.
 *
 * <p>Codex 사전 검토 Q1-Q8 반영:
 *   - 전체 product 268개 반환 (paging 없음, "전체 컬렉션 지도" 성격)
 *   - hero card = window function PARTITION BY product_id ORDER BY rarity_priority, collection_number
 *   - rarity priority = SQL CASE WHEN
 *   - 카드 이미지 URL = backend CardCdnUrls.forCard() 사용 (front 의존성 X)
 *   - 미보유 시리즈도 0/N 으로 노출 (컬렉션 동기 부여)
 *   - 신규 유저 자산 0 도 grid 그대로 (Empty state CTA 만 추가)
 *
 * <p>박스 이미지 사용 보류 (권리 리스크). hero card 이미지 cover 로 fallback.
 */
@RestController
@RequestMapping("/api/assets/dex")
@RequiredArgsConstructor
public class DexController {

    private final DexService service;

    /** 도감 메인 — product 그리드 + 보유율 + hero card cover.
     *  2026-05-29 Codex MVP — default 20, max 50. "최신 세대 우선" 정렬.
     *  2026-05-30 사용자 명시 — default 40, max 60 (테라스탈/SV 시리즈 더 노출).
     *  release_date 컬럼 추가 시 DexService 의 generationPriority 한 메서드만 교체. */
    @GetMapping
    public ReturnData<DexDto.DexMain> getDex(
            @AuthenticationPrincipal String userId,
            @RequestParam(defaultValue = "40") int limit) {
        int safeLimit = Math.min(Math.max(limit, 1), 60);
        return ReturnData.success(service.getDexMain(userId, safeLimit));
    }

    /** 시리즈 상세 — 카드 list + 보유 여부 + 힛카드 top 4. */
    @GetMapping("/{productId}")
    public ReturnData<DexDto.DexDetail> getDexDetail(
            @AuthenticationPrincipal String userId,
            @PathVariable String productId) {
        return ReturnData.success(service.getDexDetail(userId, productId));
    }
}
