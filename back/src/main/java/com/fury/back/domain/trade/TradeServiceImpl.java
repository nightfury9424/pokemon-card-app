package com.fury.back.domain.trade;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.Asset;
import com.fury.back.domain.asset.AssetImage;
import com.fury.back.domain.asset.AssetImageRepository;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.trade.dto.TradePostDto;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.domain.chat.ChatRoomRepository;
import com.fury.back.domain.chat.ChatService;
import com.fury.back.domain.interest.PostInterestRepository;
import com.fury.back.domain.notification.NotificationService;
import com.fury.back.storage.ImageStorageService;
import com.fury.back.storage.StorageKeyUrls;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class TradeServiceImpl implements TradeService {

    private final TradePostRepository tradePostRepository;
    private final BuyOrderRepository buyOrderRepository;
    private final CardRepository cardRepository;
    private final UserRepository userRepository;

    // 휴대폰 인증 게이트 토글 — Flutter OTP IPA 전엔 false(전원 차단 방지). prod에서 true로.
    @org.springframework.beans.factory.annotation.Value("${app.phone-gate.enabled:false}")
    private boolean phoneGateEnabled;
    private final com.fury.back.domain.asset.AssetRepository assetRepository;
    private final AssetImageRepository assetImageRepository;
    private final NotificationService notificationService;
    private final ImageStorageService imageStorageService;
    // Bundle 2-D: trade 상태 변경/삭제 시 chat_room에 시스템 메시지 fan-out용.
    private final ChatService chatService;
    // 거래 list engagement (chatCount / favoriteCount) batch count용.
    private final ChatRoomRepository chatRoomRepository;
    private final PostInterestRepository postInterestRepository;
    // 1인 1조회 정책 — viewerUserId != sellerId면 INSERT, UNIQUE 충돌 시 무시.
    private final TradePostViewRepository tradePostViewRepository;
    private final BlockRepository blockRepository;
    private final com.fury.back.domain.price.PriceSnapshotRepository priceSnapshotRepository;
    private final TradeSettlementRepository tradeSettlementRepository;

    @Value("${trade.image.dir}")
    private String tradeImageDir;  // Phase 1-7: legacy static handler 호환용 (신규 업로드는 ImageStorageService 사용)

    @Override
    public ReturnData<Page<TradePostDto>> getTrades(int page, int size, String cardId, String sellerId, String status, String viewerUserId) {
        PageRequest pageable = PageRequest.of(page, size);
        Page<TradePost> posts;
        final boolean hasSeller = sellerId != null && !sellerId.isBlank();
        final boolean hasCard = cardId != null && !cardId.isBlank();
        final boolean hasStatus = status != null && !status.isBlank();
        final List<String> blockedSellerIds = viewerUserId == null || viewerUserId.isBlank()
                ? List.of()
                : blockRepository.findAllByBlockerId(viewerUserId).stream()
                        .map(Block::getBlockedId)
                        .distinct()
                        .toList();
        if (!blockedSellerIds.isEmpty()) {
            List<String> statuses = hasStatus ? List.of(status) : List.of("OPEN", "RESERVED");
            posts = tradePostRepository.findFilteredExcludingSellers(
                    hasSeller ? sellerId : null,
                    hasCard ? cardId : null,
                    statuses,
                    blockedSellerIds,
                    pageable);
            return ReturnData.success(toTradePostDtoPage(posts));
        }
        // Phase 1: sellerId + cardId + status 동시 필터 우선 (기존 sellerId/cardId 단독 분기로 인한 cardId 무시 버그 해결).
        if (hasSeller && hasCard && hasStatus) {
            posts = tradePostRepository.findBySellerIdAndCardIdAndStatusOrderByCreatedAtDesc(sellerId, cardId, status, pageable);
        } else if (hasSeller && hasCard) {
            posts = tradePostRepository.findBySellerIdAndCardIdOrderByCreatedAtDesc(sellerId, cardId, pageable);
        } else if (hasSeller) {
            // 내 판매 항목 default — active(OPEN+RESERVED)만. DELETED/COMPLETED는 별도 화면.
            posts = tradePostRepository.findBySellerIdAndStatusInOrderByCreatedAtDesc(
                    sellerId, List.of("OPEN", "RESERVED"), pageable);
        } else if (hasCard) {
            posts = tradePostRepository.findOpenByCardId(cardId, pageable);
        } else {
            // status 파라미터 있으면 그대로 / 없으면 OPEN+RESERVED active 상태 (COMPLETED/DELETED 제외)
            posts = hasStatus
                    ? tradePostRepository.findByStatusOrderByCreatedAtDesc(status, pageable)
                    : tradePostRepository.findByStatusInOrderByCreatedAtDesc(List.of("OPEN", "RESERVED"), pageable);
        }

        return ReturnData.success(toTradePostDtoPage(posts));
    }

    private Page<TradePostDto> toTradePostDtoPage(Page<TradePost> posts) {
        List<String> sellerIds = posts.stream().map(TradePost::getSellerId).distinct().toList();
        List<String> cardIds = posts.stream().map(TradePost::getCardId).distinct().toList();

        Map<String, User> userMap = userRepository.findAllById(sellerIds)
                .stream().collect(Collectors.toMap(User::getUserId, Function.identity()));
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds)
                .stream().collect(Collectors.toMap(Card::getCardId, Function.identity()));

        // batch count — N+1 방지. tradeId 기준 chat_rooms / post_interests count 한 query씩.
        List<String> tradeIds = posts.stream().map(TradePost::getTradeId).distinct().toList();
        Map<String, Long> chatCountMap = tradeIds.isEmpty()
                ? Map.of()
                : chatRoomRepository.countBySaleListingIdIn(tradeIds).stream()
                        .collect(Collectors.toMap(r -> (String) r[0], r -> (Long) r[1]));
        Map<String, Long> favoriteCountMap = tradeIds.isEmpty()
                ? Map.of()
                : postInterestRepository.countByTradeIdIn(tradeIds).stream()
                        .collect(Collectors.toMap(r -> (String) r[0], r -> (Long) r[1]));

        return posts.map(post -> {
            TradePostDto dto = TradePostDto.fromWithDetails(
                    post, userMap.get(post.getSellerId()), cardMap.get(post.getCardId()));
            return dto.toBuilder()
                    .chatCount(chatCountMap.getOrDefault(post.getTradeId(), 0L))
                    .favoriteCount(favoriteCountMap.getOrDefault(post.getTradeId(), 0L))
                    .build();
        });
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> getTrade(String tradeId, String viewerUserId) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");

        // 1인 1조회 — 판매자 본인 조회는 skip. UNIQUE 충돌은 무시 (이미 본 사용자).
        if (viewerUserId != null
                && !viewerUserId.isBlank()
                && !viewerUserId.equals(post.getSellerId())
                && !tradePostViewRepository.existsByTradeIdAndUserId(tradeId, viewerUserId)) {
            try {
                tradePostViewRepository.save(TradePostView.builder()
                        .viewId(IdGenerator.generate())
                        .tradeId(tradeId)
                        .userId(viewerUserId)
                        .build());
                post.incrementViewCount();
            } catch (org.springframework.dao.DataIntegrityViolationException e) {
                // race-safe: 다른 요청이 먼저 INSERT 성공한 경우 silent.
            }
        }

        User seller = userRepository.findById(post.getSellerId()).orElse(null);
        Card card = cardRepository.findById(post.getCardId()).orElse(null);
        long chatCount = chatRoomRepository.countBySaleListingId(tradeId);
        long favoriteCount = postInterestRepository.countByTradeId(tradeId);
        TradePostDto dto = TradePostDto.fromWithDetails(post, seller, card).toBuilder()
                .chatCount(chatCount)
                .favoriteCount(favoriteCount)
                .build();
        return ReturnData.success(dto);
    }

    /** 시스템 보호 절대 상한 — 기준가 유무와 무관하게 이 금액 초과는 시장 교란으로 차단. */
    static final long ABSOLUTE_MAX_PRICE = 100_000_000L;

    /**
     * 가격 허용 범위 [하한, 상한] — 카드 종류에 따라 가드 강도 분기 (사용자 정책 2026-06-05).
     * <p><b>① KO_ESTIMATED(=KO RAW 기준가) 있음</b>(일반 카드): 기존 타이트 RAW 밴드({@link #priceBand}).
     *    시세 교란/오입력 방지. 상한은 절대상한과 min.
     * <p><b>② KO_ESTIMATED 없음</b>(프로모/PSA-only — 화면 표시값이 JP PSA10/PSA9 등 해외 graded 참고가):
     *    RAW 적정가를 판정할 KO RAW 시세가 없으므로 <b>타이트 밴드 제거</b>. 하한 없음 + 상한 = min(참고가×3, 절대상한).
     *    해외 PSA 참고가는 '적정가 밴드'가 아니라 fat-finger 방어용 느슨한 스케일로만 사용. 싼 프로모(예: 16만)는
     *    ×3=48만 상한이라 1억 통과 안 됨(전부 1억 허용은 거부). 참고가 순서 = getCardPriceSummary 프로모 분기 동일.
     * <p>③ 어떤 ref 도 없음: 보수적 절대 fallback 1천만.
     */
    static long[] resolveAllowedPriceRange(
            com.fury.back.domain.price.PriceSnapshotRepository repo, String cardId) {
        java.util.List<String> ids = java.util.List.of(cardId);
        Integer ko = firstPositivePrice(repo.findLatestKoEstimatedByCardIds(ids));
        if (ko != null) {
            long[] band = priceBand(ko);
            return new long[]{ band[0], Math.min(band[1], ABSOLUTE_MAX_PRICE) };
        }
        // RAW 기준가 없음 — 해외참고가(JP RAW → JP PSA10 → EN RAW)를 느슨한 스케일로만.
        Integer ref = firstPositivePrice(repo.findLatestScrydexJpByCardIds(ids));
        if (ref == null) ref = firstPositivePrice(repo.findLatestScrydexJpPsa10ByCardIds(ids));
        if (ref == null) ref = firstPositivePrice(repo.findLatestScrydexEnByCardIds(ids));
        long upper = (ref != null)
                ? Math.min((long) ref * 3, ABSOLUTE_MAX_PRICE)
                : 10_000_000L; // 어떤 ref 도 없음 — 보수적 fallback
        return new long[]{ 0L, upper }; // 하한 없음 (RAW 적정 하한 판정 불가)
    }

    private static Integer firstPositivePrice(
            java.util.List<com.fury.back.domain.price.PriceSnapshot> rows) {
        if (rows == null || rows.isEmpty()) return null;
        Integer price = rows.get(0).getPrice();
        return (price != null && price > 0) ? price : null;
    }

    /**
     * 매물 가격 sanity 검증 — 시장 교란 방지. 범위 밖이면 에러 메시지 반환(null=정상).
     *  - GRADED: KO 예상가가 RAW 기준이라 부정확 → skip.
     *  - 기준가({@link #resolveKoReferencePrice}) 기준 금액대별 유동 밴드: 저가는 느슨, 고가는 ±50% 수렴.
     *  - 절대 상한({@link #ABSOLUTE_MAX_PRICE}) 항상 적용. 기준가 없는 카드만 1천만 fallback.
     */
    private String validateListingPrice(String cardId, String cardStatus, int price) {
        if ("GRADED".equals(cardStatus)) return null;
        if (price > ABSOLUTE_MAX_PRICE) return "비정상적으로 높은 가격은 등록할 수 없습니다.";
        long[] range = resolveAllowedPriceRange(priceSnapshotRepository, cardId);
        if (price < range[0] || price > range[1]) {
            return "시세와 크게 동떨어진 가격은 등록할 수 없습니다.";
        }
        return null;
    }

    /** 예상가 → [하한, 상한]. 저가일수록 넓고 고가일수록 ±50% 로 좁아짐. front 와 동일 정책. */
    static long[] priceBand(int est) {
        final double up, low;
        if (est < 10_000)        { up = 5.0; low = 0.2; }
        else if (est < 100_000)  { up = 3.0; low = 0.4; }
        else if (est < 1_000_000){ up = 2.0; low = 0.5; }
        else                     { up = 1.5; low = 0.5; }
        return new long[]{ Math.round(est * low), Math.round(est * up) };
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> createTrade(String sellerId, ParameterData parameterData) {
        String cardId = parameterData.getString("cardId");
        String assetId = parameterData.getString("assetId");
        String description = parameterData.getString("description");
        if ((cardId == null || cardId.isBlank()) && (assetId == null || assetId.isBlank())) {
            return ReturnData.badRequest("cardId 또는 assetId는 필수입니다.");
        }

        if (sellerId == null || sellerId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        // 휴대폰 인증 게이트 — 거래 행위 시점에만. 클라가 코드 보고 인증 시트 띄움.
        if (phoneGateEnabled && !userRepository.findById(sellerId).map(User::isPhoneVerified).orElse(false)) {
            return ReturnData.fail("PHONE_VERIFICATION_REQUIRED", "휴대폰 인증 후 거래할 수 있어요.");
        }

        Asset asset = null;
        if (assetId != null && !assetId.isBlank()) {
            asset = assetRepository.findById(assetId).orElse(null);
            if (asset == null) return ReturnData.notFound("자산을 찾을 수 없습니다.");
            if (!sellerId.equals(asset.getUserId())) return ReturnData.fail("F403", "권한이 없습니다.");
            if (cardId == null || cardId.isBlank()) {
                cardId = asset.getCardId();
            } else if (!cardId.equals(asset.getCardId())) {
                return ReturnData.badRequest("자산의 카드 정보가 일치하지 않습니다.");
            }
        }

        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) return ReturnData.notFound("카드를 찾을 수 없습니다.");

        // 내 자산에 해당 카드가 있어야만 판매 가능
        if (asset == null) {
            boolean hasAsset = !assetRepository.findByUserIdAndCardId(sellerId, cardId).isEmpty();
            if (!hasAsset) return ReturnData.badRequest("내 자산에 등록된 카드만 판매할 수 있습니다.");
        }

        // 판매 가격 필수 (Phase 2: "가격 협의" 폐지. 호가창 ASK 쿼리는 price IS NOT NULL 조건).
        Integer price = parameterData.getInteger("price");
        if (price == null || price <= 0) {
            return ReturnData.badRequest("판매 가격은 필수입니다.");
        }

        // 동일 assetId OPEN 판매글 중복 차단 (1 자산 = 1 OPEN 판매글).
        if (assetId != null && !assetId.isBlank()) {
            // RESERVED도 active trade — 같은 자산에 active(OPEN+RESERVED) 있으면 중복 차단.
            boolean alreadyActive = tradePostRepository.findByAssetIdOrderByCreatedAtDesc(assetId)
                    .stream().anyMatch(p -> "OPEN".equals(p.getStatus()) || "RESERVED".equals(p.getStatus()));
            if (alreadyActive) {
                return ReturnData.fail("E409", "이미 판매 중인 판매글이 있어요. 기존 판매글을 수정하거나 취소해주세요.");
            }
        }

        String cardStatus = parameterData.getString("cardStatus");
        String condition = parameterData.getString("condition");
        String gradingCompany = parameterData.getString("gradingCompany");
        String gradeValue = parameterData.getString("gradeValue");
        String certNumber = parameterData.getString("certNumber");
        if (cardStatus == null && asset != null && asset.getCardStatus() != null) {
            cardStatus = asset.getCardStatus();
        }
        if (condition == null && asset != null && asset.getEstimatedGrade() != null) {
            condition = String.format("%.1f", asset.getEstimatedGrade().doubleValue());
        }
        // 가격 sanity 검증 (시장 교란 방지) — front 우회 방지용 서버측 가드.
        String priceErr = validateListingPrice(cardId, cardStatus, price);
        if (priceErr != null) return ReturnData.badRequest(priceErr);
        String effectiveGradingCompany = gradingCompany != null
                ? gradingCompany
                : asset != null ? asset.getGradingCompany() : null;
        String effectiveGradeValue = gradeValue != null
                ? gradeValue
                : asset != null ? asset.getGradeValue() : null;
        String rarity = card.getRarityCode() != null && !card.getRarityCode().isBlank()
                ? card.getRarityCode()
                : "-";
        boolean graded = "GRADED".equals(cardStatus);
        String titleSuffix = graded && effectiveGradingCompany != null && effectiveGradeValue != null
                ? effectiveGradingCompany + " " + effectiveGradeValue
                : "RAW 직거래";
        String title = card.getName() + " [" + rarity + "] - " + titleSuffix;

        TradePost post = TradePost.builder()
                .tradeId(IdGenerator.generate())
                .sellerId(sellerId)
                .cardId(cardId)
                .assetId(asset != null ? asset.getAssetId() : null)
                .title(title)
                .description(description)
                .price(price)
                .cardStatus(cardStatus != null ? cardStatus : "RAW")
                .condition(condition)
                .gradingCompany(effectiveGradingCompany)
                .gradeValue(effectiveGradeValue)
                .certNumber(certNumber != null ? certNumber : asset != null ? asset.getCertNumber() : null)
                .build();

        post = tradePostRepository.save(post);

        User seller = userRepository.findById(sellerId).orElse(null);

        // 같은 카드에 OPEN 매수 호가 등록한 사용자들에게 알림 (본인 제외)
        try {
            final String cardIdFinal = cardId;
            final Integer priceFinal = post.getPrice();
            if (priceFinal != null) {
                var buyerIds = buyOrderRepository.findOpenByCardIdOrderByBidPriceDesc(cardIdFinal)
                        .stream()
                        .map(BuyOrder::getBuyerId)
                        .filter(uid -> uid != null && !uid.equals(sellerId))
                        .distinct()
                        .toList();
                if (!buyerIds.isEmpty()) {
                    String sellerNickname = seller != null ? seller.getNickname() : "판매자";
                    notificationService.notifyTradePostToBuyers(buyerIds, cardIdFinal, card.getName(), priceFinal, sellerNickname);
                }
            }
        } catch (Exception ignore) {}

        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> createTradeFromAsset(String sellerId, ParameterData parameterData) {
        String assetId = parameterData.getString("assetId");
        Integer price = parameterData.getInteger("price");
        String optionalMemo = parameterData.getString("optionalMemo");
        if (optionalMemo == null) {
            optionalMemo = parameterData.getString("memo");
        }

        if (sellerId == null || sellerId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        // 휴대폰 인증 게이트 (거래 행위 시점).
        if (phoneGateEnabled && !userRepository.findById(sellerId).map(User::isPhoneVerified).orElse(false)) {
            return ReturnData.fail("PHONE_VERIFICATION_REQUIRED", "휴대폰 인증 후 거래할 수 있어요.");
        }
        if (assetId == null || assetId.isBlank() || price == null) {
            return ReturnData.badRequest("assetId, price는 필수입니다.");
        }

        Asset asset = assetRepository.findById(assetId).orElse(null);
        if (asset == null) return ReturnData.notFound("자산을 찾을 수 없습니다.");
        if (!sellerId.equals(asset.getUserId())) return ReturnData.fail("F403", "권한이 없습니다.");

        Card card = cardRepository.findById(asset.getCardId()).orElse(null);
        if (card == null) return ReturnData.notFound("카드를 찾을 수 없습니다.");

        // RESERVED도 active — OPEN+RESERVED 기존 trade 있으면 그걸 반환.
        // CLOSED 복구 로직은 제거 (legacy 상태값. 정책상 OPEN/RESERVED/COMPLETED/DELETED만 사용).
        List<TradePost> existingPosts = tradePostRepository.findByAssetIdOrderByCreatedAtDesc(assetId);
        TradePost activePost = existingPosts.stream()
                .filter(post -> "OPEN".equals(post.getStatus()) || "RESERVED".equals(post.getStatus()))
                .findFirst()
                .orElse(null);
        if (activePost != null) {
            User seller = userRepository.findById(sellerId).orElse(null);
            return ReturnData.success(TradePostDto.fromWithDetails(activePost, seller, card));
        }

        // 가격 sanity 검증 (시장 교란 방지).
        String priceErr = validateListingPrice(asset.getCardId(), asset.getCardStatus(), price);
        if (priceErr != null) return ReturnData.badRequest(priceErr);

        String rarity = card.getRarityCode() != null && !card.getRarityCode().isBlank()
                ? card.getRarityCode()
                : "-";
        boolean graded = "GRADED".equals(asset.getCardStatus());
        String titleSuffix = graded && asset.getGradingCompany() != null && asset.getGradeValue() != null
                ? asset.getGradingCompany() + " " + asset.getGradeValue()
                : "RAW 직거래";
        String title = card.getName() + " [" + rarity + "] - " + titleSuffix;

        List<AssetImage> assetImages = assetImageRepository.findByAssetId(assetId);
        String imageUrl = assetImages.stream()
                .filter(image -> "SLAB".equals(image.getImageType()))
                .findFirst()
                .map(AssetImage::getImageUrl)
                .orElseGet(() -> assetImages.stream()
                        .filter(image -> "FRONT".equals(image.getImageType()))
                        .findFirst()
                        .map(AssetImage::getImageUrl)
                        .orElse(null));

        TradePost post = TradePost.builder()
                .tradeId(IdGenerator.generate())
                .sellerId(sellerId)
                .cardId(asset.getCardId())
                .assetId(assetId)
                .title(title)
                .description(buildAssetTradeDescription(asset, optionalMemo))
                .price(price)
                .cardStatus(asset.getCardStatus() != null ? asset.getCardStatus() : "RAW")
                .gradingCompany(asset.getGradingCompany())
                .gradeValue(asset.getGradeValue())
                .certNumber(asset.getCertNumber())
                .imageUrl(imageUrl)
                .build();

        post = tradePostRepository.save(post);

        User seller = userRepository.findById(sellerId).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> updateTrade(String tradeId, String userId, ParameterData parameterData) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        // 수정 시 가격도 sanity 검증 (정상 등록 후 99.9M 으로 변경 차단).
        Integer newPrice = parameterData.getInteger("price");
        if (newPrice != null && newPrice > 0) {
            String updErr = validateListingPrice(post.getCardId(), post.getCardStatus(), newPrice);
            if (updErr != null) return ReturnData.badRequest(updErr);
        }
        post.update(parameterData.getString("title"), parameterData.getString("description"),
                newPrice);
        String condition = parameterData.getString("condition");
        if (condition != null) {
            // 3차-C: EntityManager 직접 UPDATE + refresh → setter + dirty checking으로 단순화
            post.updateCondition(condition);
        }

        User seller = userRepository.findById(post.getSellerId()).orElse(null);
        Card card = cardRepository.findById(post.getCardId()).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<Void> deleteTrade(String tradeId, String userId) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        // Bundle 2-A.7: hard delete 금지 — soft delete (status='DELETED' + deleted_at=now).
        // 채팅방 미니카드/메시지 보존 → 분쟁/신고 근거 유지.
        // 일반 거래 목록/검색은 status='OPEN' 필터로 자동 제외.
        post.markDeleted();
        // Bundle 2-D: 모든 chat_room에 "판매글이 삭제되었습니다." 시스템 메시지 broadcast.
        chatService.broadcastTradeStatusChanged(tradeId, "DELETED");
        return ReturnData.success();
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> updateStatus(String tradeId, String userId, String status, String chatRoomId) {
        if (status == null || status.isBlank()) {
            return ReturnData.badRequest("status는 필수입니다.");
        }
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        // same-status no-op — 현재 status와 동일한 요청이면 DB update + SYSTEM 메시지 생성 X.
        // 동일 상태 변경 클릭 시 시스템 메시지 중복 방지.
        if (status.equals(post.getStatus())) {
            User seller = userRepository.findById(post.getSellerId()).orElse(null);
            Card card = cardRepository.findById(post.getCardId()).orElse(null);
            return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
        }

        // B2-4: OPEN→COMPLETED 직접 금지 — 거래중(예약, 상대 선택) 거쳐야 완료 가능.
        if ("COMPLETED".equals(status) && "OPEN".equals(post.getStatus())) {
            return ReturnData.fail("F409", "거래중(예약)으로 변경한 뒤 완료할 수 있어요.");
        }

        post.updateStatus(status);

        // 거래중 모델 — active_chat_room_id 처리:
        // - RESERVED + chatRoomId NOT NULL → 거래 상대 지정 (선택된 chat 만 입력 가능)
        // - RESERVED + chatRoomId NULL → 기존 호환 (active 변경 X)
        // - OPEN 복귀 → clear (모든 buyer 다시 채팅 가능)
        // - COMPLETED / DELETED → 그대로 (선택 상대 후속 대화 정책)
        if ("RESERVED".equals(status) && chatRoomId != null && !chatRoomId.isBlank()) {
            post.setActiveChatRoom(chatRoomId);
        } else if ("OPEN".equals(status)) {
            post.clearActiveChatRoom();
        }

        // Bundle 2-D: 모든 chat_room에 상태 변경 시스템 메시지 broadcast.
        // (OPEN/RESERVED/COMPLETED → 카피 분기, 그 외 silent)
        chatService.broadcastTradeStatusChanged(tradeId, status);

        User seller = userRepository.findById(post.getSellerId()).orElse(null);
        Card card = cardRepository.findById(post.getCardId()).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    // ── 실거래가 수집 (APP_TRADE 원천). 거래 완료 후 양쪽 당사자 입력. 시세 반영은 후속 배치. ──

    /** 매칭 buyer = activeChatRoom 의 buyerUserId (지정된 거래 상대). 없으면 null. */
    private String settlementBuyerOf(TradePost post) {
        final String acr = post.getActiveChatRoomId();
        if (acr == null || acr.isBlank()) return null;
        return chatRoomRepository.findById(acr).map(r -> r.getBuyerUserId()).orElse(null);
    }

    /** userId 의 거래 역할 — SELLER / BUYER / null(당사자 아님). */
    private String settlementRoleOf(TradePost post, String userId) {
        if (userId != null && userId.equals(post.getSellerId())) return "SELLER";
        final String buyer = settlementBuyerOf(post);
        if (buyer != null && buyer.equals(userId)) return "BUYER";
        return null;
    }

    private com.fury.back.domain.trade.dto.TradeSettlementStatusDto buildSettlementStatus(
            TradePost post, String userId) {
        final String role = settlementRoleOf(post, userId);
        final boolean participant = role != null;
        final boolean completed = "COMPLETED".equals(post.getStatus());
        final TradeSettlement existing = participant
                ? tradeSettlementRepository.findByTradeIdAndUserId(post.getTradeId(), userId).orElse(null)
                : null;
        final boolean reported = existing != null;
        final boolean required = participant && completed && !reported;
        return new com.fury.back.domain.trade.dto.TradeSettlementStatusDto(
                participant, completed, reported, required,
                post.getPrice(),
                existing != null ? existing.getReportedPrice() : null,
                role);
    }

    /**
     * 실거래가 도메인 검증 (B3-1) — "말도 안 되는 값"(garbage) 차단. 백엔드 최종 게이트(API 직접 호출 방어).
     * <p>거름: 1,000원 미만(0·1·15 등), 100원 단위 아님(1004·15·11111111 등), 절대 상한 초과(99999999999 등).
     * <p>희망가 대비 밴드는 적용하지 않음 — 실거래가 희망가와 크게 다를 수 있어(협상/상태차) 정상 데이터를
     *    버릴 위험. 단위/상한 sanity 만 강제. (희망가가 비-100원 단위면 정확히 일치 시 단위 예외.)
     * @return 위반 시 사용자 문구, 통과 시 null.
     */
    private String validateSettlementAmount(int price, Integer listingPrice) {
        if (price < 1000) return "거래 금액은 1,000원 이상 입력해주세요.";
        if (price > 1_000_000_000) return "금액이 올바르지 않습니다.";
        // 희망가와 정확히 일치하면(이 금액이 맞아요) 단위 검증 예외 — 희망가가 비-100원 단위일 수 있음.
        final boolean trusted = listingPrice != null && price == listingPrice;
        if (!trusted && price % 100 != 0) return "거래 금액은 100원 단위로 입력해주세요.";
        return null;
    }

    @Override
    @Transactional(readOnly = true)
    public ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> getSettlementStatus(
            String tradeId, String userId) {
        final TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        return ReturnData.success(buildSettlementStatus(post, userId));
    }

    @Override
    @Transactional
    public ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> submitSettlement(
            String tradeId, String userId, Integer price) {
        if (price == null) return ReturnData.badRequest("거래 금액을 입력해주세요.");
        final TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        final String role = settlementRoleOf(post, userId);
        if (role == null) return ReturnData.fail("F403", "거래 당사자만 입력할 수 있습니다.");
        if (!"COMPLETED".equals(post.getStatus())) {
            return ReturnData.fail("F409", "완료된 거래만 입력할 수 있습니다.");
        }
        // B3-1: 실거래가 도메인 검증 — 시세 오염 방지. 위반 시 400, 저장 X.
        final String amtErr = validateSettlementAmount(price, post.getPrice());
        if (amtErr != null) return ReturnData.badRequest(amtErr);
        TradeSettlement s = tradeSettlementRepository.findByTradeIdAndUserId(tradeId, userId).orElse(null);
        if (s == null) {
            s = TradeSettlement.builder()
                    .settlementId(IdGenerator.generate())
                    .tradeId(tradeId)
                    .userId(userId)
                    .role(role)
                    .cardId(post.getCardId())
                    .reportedPrice(price)
                    .build();
        } else {
            s.updatePrice(price);
        }
        tradeSettlementRepository.save(s);
        // 시세(APP_TRADE) 반영은 후속 '마지막 리터치' — 여기선 수집/저장만 (v6 freeze 보호).
        return ReturnData.success(buildSettlementStatus(post, userId));
    }

    // ── B2-12: 구매(BuyOrder) 실거래가 수집 — SALE 대칭. trade_settlements 에 trade_id=buyOrderId 저장. ──

    /** BUY 거래중 상대(seller) = activeChatRoom 의 sellerUserId. */
    private String buySettlementSellerOf(BuyOrder order) {
        final String acr = order.getActiveChatRoomId();
        if (acr == null || acr.isBlank()) return null;
        return chatRoomRepository.findById(acr).map(r -> r.getSellerUserId()).orElse(null);
    }

    /** BUY 거래의 userId 역할 — BUYER(호가 작성자) / SELLER(선택 상대) / null. */
    private String buySettlementRoleOf(BuyOrder order, String userId) {
        if (userId != null && userId.equals(order.getBuyerId())) return "BUYER";
        final String seller = buySettlementSellerOf(order);
        if (seller != null && seller.equals(userId)) return "SELLER";
        return null;
    }

    private com.fury.back.domain.trade.dto.TradeSettlementStatusDto buildBuySettlementStatus(
            BuyOrder order, String userId) {
        final String role = buySettlementRoleOf(order, userId);
        final boolean participant = role != null;
        final boolean completed = "COMPLETED".equals(order.getStatus());
        final TradeSettlement existing = participant
                ? tradeSettlementRepository.findByTradeIdAndUserId(order.getBuyOrderId(), userId).orElse(null)
                : null;
        final boolean reported = existing != null;
        final boolean required = participant && completed && !reported;
        return new com.fury.back.domain.trade.dto.TradeSettlementStatusDto(
                participant, completed, reported, required,
                order.getBidPrice(),
                existing != null ? existing.getReportedPrice() : null,
                role);
    }

    @Override
    @Transactional(readOnly = true)
    public ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> getBuySettlementStatus(
            String buyOrderId, String userId) {
        final BuyOrder order = buyOrderRepository.findById(buyOrderId).orElse(null);
        if (order == null) return ReturnData.notFound("매수 호가를 찾을 수 없습니다.");
        return ReturnData.success(buildBuySettlementStatus(order, userId));
    }

    @Override
    @Transactional
    public ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> submitBuySettlement(
            String buyOrderId, String userId, Integer price) {
        if (price == null) return ReturnData.badRequest("거래 금액을 입력해주세요.");
        final BuyOrder order = buyOrderRepository.findById(buyOrderId).orElse(null);
        if (order == null) return ReturnData.notFound("매수 호가를 찾을 수 없습니다.");
        final String role = buySettlementRoleOf(order, userId);
        if (role == null) return ReturnData.fail("F403", "거래 당사자만 입력할 수 있습니다.");
        if (!"COMPLETED".equals(order.getStatus())) {
            return ReturnData.fail("F409", "완료된 거래만 입력할 수 있습니다.");
        }
        // B3-1: 실거래가 도메인 검증 — 시세 오염 방지. 위반 시 400, 저장 X.
        final String amtErr = validateSettlementAmount(price, order.getBidPrice());
        if (amtErr != null) return ReturnData.badRequest(amtErr);
        TradeSettlement s = tradeSettlementRepository.findByTradeIdAndUserId(buyOrderId, userId).orElse(null);
        if (s == null) {
            s = TradeSettlement.builder()
                    .settlementId(IdGenerator.generate())
                    .tradeId(buyOrderId)
                    .userId(userId)
                    .role(role)
                    .cardId(order.getCardId())
                    .reportedPrice(price)
                    .build();
        } else {
            s.updatePrice(price);
        }
        tradeSettlementRepository.save(s);
        return ReturnData.success(buildBuySettlementStatus(order, userId));
    }

    /**
     * 거래중 모델: 판매자만 호출. 판매글에 연결된 채팅방 list → 거래 상대 선택 sheet 용.
     * 차단된 user 는 제외. lastMessage / lastMessageAt 으로 정렬 (최근 활성 채팅 먼저).
     */
    @Override
    @Transactional(readOnly = true)
    public ReturnData<java.util.List<com.fury.back.domain.trade.dto.ChatPartnerDto>> getChatPartners(
            String tradeId, String userId) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        java.util.List<com.fury.back.domain.chat.ChatRoom> rooms =
                chatRoomRepository.findAllBySaleListingId(tradeId);
        java.util.Set<String> blockedByMe = blockRepository.findAllByBlockerId(userId).stream()
                .map(com.fury.back.domain.block.Block::getBlockedId)
                .collect(java.util.stream.Collectors.toSet());
        java.util.List<String> buyerIds = rooms.stream()
                .map(com.fury.back.domain.chat.ChatRoom::getBuyerUserId)
                .filter(id -> !blockedByMe.contains(id))
                .distinct()
                .toList();
        java.util.Map<String, User> userMap = userRepository.findAllById(buyerIds).stream()
                .collect(java.util.stream.Collectors.toMap(User::getUserId, u -> u));

        java.util.List<com.fury.back.domain.trade.dto.ChatPartnerDto> partners = rooms.stream()
                .filter(r -> !blockedByMe.contains(r.getBuyerUserId()))
                .map(r -> {
                    User buyer = userMap.get(r.getBuyerUserId());
                    return new com.fury.back.domain.trade.dto.ChatPartnerDto(
                            r.getChatRoomId(),
                            r.getBuyerUserId(),
                            buyer != null ? buyer.getNickname() : null,
                            buyer != null ? buyer.getProfileImageUrl() : null,
                            r.getLastMessage(),
                            r.getLastMessageAt());
                })
                .sorted((a, b) -> {
                    if (a.lastMessageAt() == null && b.lastMessageAt() == null) return 0;
                    if (a.lastMessageAt() == null) return 1;
                    if (b.lastMessageAt() == null) return -1;
                    return b.lastMessageAt().compareTo(a.lastMessageAt());
                })
                .toList();
        return ReturnData.success(partners);
    }

    /**
     * MY > 내 판매 내역 — sellerId 본인의 OPEN/RESERVED/COMPLETED 이력.
     * DELETED 숨김. 기존 active list method (OPEN+RESERVED) 와 분리된 별도 history view.
     * sellerId 는 controller 의 @AuthenticationPrincipal 기준 — IDOR 방지.
     */
    @Override
    @Transactional(readOnly = true)
    public ReturnData<Page<TradePostDto>> getMyHistory(String sellerId, int page, int size) {
        if (sellerId == null || sellerId.isBlank()) {
            return ReturnData.fail("F403", "인증이 필요합니다.");
        }
        Pageable pageable = PageRequest.of(page, size);
        Page<TradePost> posts = tradePostRepository.findBySellerIdAndStatusInOrderByCreatedAtDesc(
                sellerId, List.of("OPEN", "RESERVED", "COMPLETED"), pageable);
        return ReturnData.success(toTradePostDtoPage(posts));
    }

    @Override
    @Transactional
    public ReturnData<String> uploadImage(String tradeId, String userId, MultipartFile file) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        try {
            // Phase 1-7: ImageStorageService 사용 (local=disk / prod=S3).
            // DB에는 storage key 저장. 응답은 /api/images/secure/{key} proxy URL.
            String key = imageStorageService.store(
                    "uploads/trade/" + tradeId,
                    file.getOriginalFilename(),
                    file
            );
            if (post.getImageUrl() == null || post.getImageUrl().isBlank()) {
                post.updateImageUrl(key);
            } else {
                post.updateImageUrl(post.getImageUrl() + "," + key);
            }
            return ReturnData.success(StorageKeyUrls.toProxyUrl(key));
        } catch (IOException e) {
            return ReturnData.fail("F500", "이미지 저장 실패: " + e.getMessage());
        }
    }

    @Override
    public ReturnData<List<Map<String, Object>>> getCardTradeSummaries(int size) {
        PageRequest pageable = PageRequest.of(0, size);
        List<Object[]> rows = tradePostRepository.findCardTradeSummary(pageable);

        List<String> cardIds = rows.stream().map(r -> (String) r[0]).toList();
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds)
                .stream().collect(Collectors.toMap(Card::getCardId, Function.identity()));

        List<Map<String, Object>> result = rows.stream().map(row -> {
            String cardId = (String) row[0];
            long count = ((Number) row[1]).longValue();
            int avgPrice = ((Number) row[2]).intValue();
            int minPrice = ((Number) row[3]).intValue();
            Card card = cardMap.get(cardId);

            Map<String, Object> item = new java.util.LinkedHashMap<>();
            item.put("cardId", cardId);
            item.put("sellerCount", count);
            item.put("avgPrice", avgPrice);
            item.put("minPrice", minPrice);
            if (card != null) {
                item.put("name", card.getName());
                item.put("rarityCode", card.getRarityCode());
                item.put("imageUrl", card.getImageUrl());
                item.put("jpScrydexRef", card.getJpScrydexRef());
                item.put("enScrydexRef", card.getEnScrydexRef());
            }
            return item;
        }).toList();

        return ReturnData.success(result);
    }

    private String getExtension(String filename) {
        if (filename == null) return ".jpg";
        int idx = filename.lastIndexOf('.');
        return idx >= 0 ? filename.substring(idx) : ".jpg";
    }

    private String buildAssetTradeDescription(Asset asset, String optionalMemo) {
        StringBuilder description = new StringBuilder();
        description.append("자산 기반 자동 판매 등록입니다.");
        description.append("\n상태: ").append(asset.getCardStatus() != null ? asset.getCardStatus() : "RAW");

        if (asset.getGradingCompany() != null || asset.getGradeValue() != null) {
            description.append("\n공식 등급: ");
            if (asset.getGradingCompany() != null) description.append(asset.getGradingCompany());
            if (asset.getGradeValue() != null) description.append(" ").append(asset.getGradeValue());
        }
        if (asset.getEstimatedGrade() != null) {
            description.append("\n앱 분석 등급: ").append(asset.getEstimatedGrade()).append("점");
        }
        if (asset.getCenteringScore() != null) {
            description.append("\n센터링: ").append(asset.getCenteringScore()).append("점");
            if (asset.getCenteringRatio() != null && !asset.getCenteringRatio().isBlank()) {
                description.append(" (").append(asset.getCenteringRatio()).append(")");
            }
        }
        if (asset.getCornerScore() != null) {
            description.append("\n코너: ").append(asset.getCornerScore()).append("점");
        }
        if (asset.getSurfaceScore() != null) {
            description.append("\n표면: ").append(asset.getSurfaceScore()).append("점");
        }
        if (asset.getWhiteningScore() != null) {
            description.append("\n화이트닝: ").append(asset.getWhiteningScore()).append("점");
        }
        if (optionalMemo != null && !optionalMemo.isBlank()) {
            description.append("\n\n메모: ").append(optionalMemo.trim());
        }
        return description.toString();
    }
}
