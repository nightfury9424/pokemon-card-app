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

        post.update(parameterData.getString("title"), parameterData.getString("description"),
                parameterData.getInteger("price"));
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
