package com.fury.back.domain.chat;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ConversationStateDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.chat.event.ChatReadEvent;
import com.fury.back.domain.chat.event.SystemMessageEvent;
import com.fury.back.domain.trade.BuyOrder;
import com.fury.back.domain.trade.BuyOrderRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.storage.CardCdnUrls;
import com.fury.back.storage.ImageStorageService;
import com.fury.back.storage.StorageKeyUrls;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@Slf4j
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChatServiceImpl implements ChatService {

    private final ChatRoomRepository chatRoomRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final TradePostRepository tradePostRepository;
    // 2026-05-28 BUY chat — BuyOrder context 조회 (가격/상태/cardId) + getOrCreateRoomFromBuyOrder.
    private final BuyOrderRepository buyOrderRepository;
    private final UserRepository userRepository;
    private final ApplicationEventPublisher eventPublisher;
    // Bundle 2-A: 거래 미니카드용 카드 마스터 이미지 조립 (#62 CardCdnUrls 재활용).
    private final CardRepository cardRepository;
    private final CardCdnUrls cardCdnUrls;
    private final BlockRepository blockRepository;
    // 2026-05-28 이미지 메시지 — S3 store + magic 검증 + DB save.
    private final ImageStorageService imageStorageService;

    @Override
    @Transactional
    public ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId) {
        TradePost trade = tradePostRepository.findById(saleListingId)
                .orElseThrow(() -> new IllegalArgumentException("거래글 없음: " + saleListingId));

        // self-chat 차단 — 본인 판매글에는 본인이 채팅방을 만들 수 없음.
        // front도 _isSeller로 채팅하기 버튼 숨기지만, API 직접 호출 차단용 backend 가드.
        if (trade.getSellerId().equals(buyerUserId)) {
            throw new IllegalStateException("본인이 등록한 판매글에는 채팅을 시작할 수 없습니다.");
        }
        requireNotBlocked(buyerUserId, trade.getSellerId());

        // Bundle 2-A.2: (saleListingId, buyerUserId) 1:1 unique 채팅방 정책.
        // DB UNIQUE 인덱스(uq_chat_rooms_sale_buyer) + race-safe 가드 — 동시 요청 시
        // 첫 lookup empty 두 번째도 empty라 둘 다 save 시도해도 DB UNIQUE violation으로
        // 두 번째가 fail → catch 후 다시 findBy* 호출하면 첫 번째 row 반환.
        //
        // Bundle 2-A.6: 신규 채팅방 생성은 OPEN 거래만 허용 (비즈니스 룰).
        // 기존 채팅방은 status 무관 반환 — 이미 대화 중인 buyer는 진행/배송/분쟁 대화 계속 필요.
        // 프론트 CTA disabled와 별개로 백엔드도 가드 (악의 API 직접 호출 차단).
        //
        // Bundle 2-D: 신규 room 생성 직후 첫 시스템 메시지로 사기 주의 안내 자동 1회.
        // race-safe catch 후 기존 room 반환 시는 X (orElseGet save 성공 직후만).
        final boolean[] newlyCreated = {false};
        ChatRoom room = chatRoomRepository
                .findBySaleListingIdAndBuyerUserId(saleListingId, buyerUserId)
                .orElseGet(() -> {
                    if (!"OPEN".equals(trade.getStatus())) {
                        // Phase 1 hotfix#6: status 별 명확한 HTTP code + reason (RFC 9110).
                        // - 410 GONE = TRADE_DELETED (영구 제거)
                        // - 409 CONFLICT = TRADE_RESERVED/COMPLETED (상태 충돌, 일시적)
                        throw switch (trade.getStatus()) {
                            case "RESERVED" -> new ResponseStatusException(HttpStatus.CONFLICT, "TRADE_RESERVED");
                            case "COMPLETED" -> new ResponseStatusException(HttpStatus.CONFLICT, "TRADE_COMPLETED");
                            case "DELETED" -> new ResponseStatusException(HttpStatus.GONE, "TRADE_DELETED");
                            default -> new ResponseStatusException(HttpStatus.CONFLICT, "TRADE_UNAVAILABLE");
                        };
                    }
                    try {
                        ChatRoom saved = chatRoomRepository.saveAndFlush(ChatRoom.builder()
                                .chatRoomId(IdGenerator.generate())
                                .saleListingId(saleListingId)
                                .sellerUserId(trade.getSellerId())
                                .buyerUserId(buyerUserId)
                                .build());
                        newlyCreated[0] = true;
                        return saved;
                    } catch (org.springframework.dao.DataIntegrityViolationException e) {
                        // 동시 요청 race — 다른 요청이 먼저 생성. 그 row를 가져옴.
                        return chatRoomRepository
                                .findBySaleListingIdAndBuyerUserId(saleListingId, buyerUserId)
                                .orElseThrow(() -> e);
                    }
                });

        // Bundle 2-D: 신규 생성 시점에만 사기 주의 시스템 메시지 자동 1회.
        if (newlyCreated[0]) {
            sendSystemMessage(room.getChatRoomId(),
                    "⚠ 안전한 거래를 위해 외부 송금이나 개인정보 요구에 주의해주세요.");
        } else {
            // Phase 1 hotfix: existing room 재진입 시
            // - 상대(seller) hidden_at NOT NULL → 재초대 차단 403 (보내는 척 금지)
            // - 본인(buyer) hidden_at NOT NULL → clear (사용자가 다시 채팅 시작)
            if (room.getSellerHiddenAt() != null) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN, "OTHER_LEFT");
            }
            if (room.getBuyerHiddenAt() != null) {
                room.clearHiddenForUser(buyerUserId);
                chatRoomRepository.save(room);
            }
        }

        User other = userRepository.findById(trade.getSellerId()).orElse(null);
        long unread = chatMessageRepository
                .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), buyerUserId);

        // Bundle 2-A: 카드 마스터 이미지 조립. card 매칭 부재 시 null (프론트 placeholder).
        Card card = trade.getCardId() != null
                ? cardRepository.findById(trade.getCardId()).orElse(null)
                : null;
        String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;
        String cardName = card != null ? card.getName() : null;

        return ChatRoomDto.fromSale(room, buyerUserId,
                trade.getTitle(), StorageKeyUrls.firstProxyUrl(trade.getImageUrl()),
                other != null ? other.getNickname() : "",
                other != null ? other.getProfileImageUrl() : "",
                unread,
                trade.getStatus(), trade.getPrice(), cardImageUrl, cardName);
    }

    /**
     * 2026-05-28 BuyOrder 양방향 채팅 — 잠재 판매자가 BuyOrder 작성자에게 채팅 시작.
     *
     * <p>패턴은 {@link #getOrCreateRoom} (SALE) 과 동일:
     * <ul>
     *   <li>self-chat 차단 — BuyOrder.buyerId == sellerUserId 이면 IllegalState
     *   <li>양방향 차단 검증 — requireNotBlocked
     *   <li>race-safe save + DataIntegrityViolationException catch
     *   <li>신규 방 생성 시 사기 주의 SYSTEM 메시지 1회
     *   <li>existing 방 재진입 시 본인 hidden_at clear / 상대(buyer=BuyOrder 작성자) hidden_at → 403 OTHER_LEFT
     * </ul>
     *
     * <p>BUY chat의 buyer_user_id = BuyOrder.buyerId (카드 사려는 사람, 채팅 받는 사람),
     * seller_user_id = sellerUserId (카드 팔려는 사람, 채팅 시작자). 명명 일관 (Codex A).
     */
    @Override
    @Transactional
    public ChatRoomDto getOrCreateRoomFromBuyOrder(String buyOrderId, String sellerUserId) {
        BuyOrder buyOrder = buyOrderRepository.findById(buyOrderId)
                .orElseThrow(() -> new IllegalArgumentException("구매 호가 없음: " + buyOrderId));

        if (buyOrder.getBuyerId().equals(sellerUserId)) {
            throw new IllegalStateException("본인이 등록한 구매 호가에는 채팅을 시작할 수 없습니다.");
        }
        requireNotBlocked(sellerUserId, buyOrder.getBuyerId());

        final boolean[] newlyCreated = {false};
        ChatRoom room = chatRoomRepository
                .findByBuyOrderIdAndSellerUserId(buyOrderId, sellerUserId)
                .orElseGet(() -> {
                    // BuyOrder.status = OPEN/MATCHED/CANCELED. 신규 방은 OPEN 한정.
                    if (!"OPEN".equals(buyOrder.getStatus())) {
                        throw switch (buyOrder.getStatus()) {
                            case "MATCHED" -> new ResponseStatusException(HttpStatus.CONFLICT, "BUY_ORDER_MATCHED");
                            case "CANCELED" -> new ResponseStatusException(HttpStatus.GONE, "BUY_ORDER_CANCELED");
                            default -> new ResponseStatusException(HttpStatus.CONFLICT, "BUY_ORDER_UNAVAILABLE");
                        };
                    }
                    try {
                        ChatRoom saved = chatRoomRepository.saveAndFlush(ChatRoom.builder()
                                .chatRoomId(IdGenerator.generate())
                                .saleListingId(null)
                                .buyOrderId(buyOrderId)
                                .sellerUserId(sellerUserId)
                                .buyerUserId(buyOrder.getBuyerId())
                                .build());
                        newlyCreated[0] = true;
                        return saved;
                    } catch (org.springframework.dao.DataIntegrityViolationException e) {
                        return chatRoomRepository
                                .findByBuyOrderIdAndSellerUserId(buyOrderId, sellerUserId)
                                .orElseThrow(() -> e);
                    }
                });

        if (newlyCreated[0]) {
            sendSystemMessage(room.getChatRoomId(),
                    "⚠ 안전한 거래를 위해 외부 송금이나 개인정보 요구에 주의해주세요.");
        } else {
            // 기존 room 재진입 — 상대(buyer=BuyOrder 작성자) hidden_at NOT NULL → 재초대 차단.
            if (room.getBuyerHiddenAt() != null) {
                throw new ResponseStatusException(HttpStatus.FORBIDDEN, "OTHER_LEFT");
            }
            if (room.getSellerHiddenAt() != null) {
                room.clearHiddenForUser(sellerUserId);
                chatRoomRepository.save(room);
            }
        }

        User other = userRepository.findById(buyOrder.getBuyerId()).orElse(null);
        long unread = chatMessageRepository
                .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), sellerUserId);
        Card card = buyOrder.getCardId() != null
                ? cardRepository.findById(buyOrder.getCardId()).orElse(null)
                : null;
        String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;
        String cardName = card != null ? card.getName() : null;

        return ChatRoomDto.fromBuy(room, sellerUserId,
                cardName != null ? cardName : "",
                other != null ? other.getNickname() : "",
                other != null ? other.getProfileImageUrl() : "",
                unread,
                buyOrder.getStatus(), buyOrder.getBidPrice(), cardImageUrl);
    }

    @Override
    public List<ChatRoomDto> getMyRooms(String userId) {
        // Phase 1 hotfix #2: 차단 자바 단 필터 제거. 차단 ≠ list hide (정책).
        // list 노출 통제는 오직 hidden_at (findMyRooms JPQL이 본인 hidden_at IS NULL 분기).
        // 차단 user 방도 list 그대로 노출. 입력 비활성화는 conversation-state 응답에서.
        List<ChatRoom> rooms = chatRoomRepository.findMyRooms(userId);

        // 필요한 userId 수집
        List<String> userIds = rooms.stream()
                .flatMap(r -> java.util.stream.Stream.of(r.getBuyerUserId(), r.getSellerUserId()))
                .distinct().toList();
        Map<String, User> userMap = userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u));

        // 2026-05-28: SALE chat 방은 sale_listing_id NOT NULL, BUY chat 방은 buy_order_id NOT NULL.
        // 두 그룹 분리 후 각각 batch fetch (N+1 차단 + tradePostRepository.findAllById null 차단 — Codex B).
        List<String> tradeIds = rooms.stream()
                .map(ChatRoom::getSaleListingId)
                .filter(id -> id != null && !id.isBlank())
                .distinct().toList();
        Map<String, TradePost> tradeMap = tradeIds.isEmpty()
                ? Map.of()
                : tradePostRepository.findAllById(tradeIds).stream()
                        .collect(Collectors.toMap(TradePost::getTradeId, t -> t));

        List<String> buyOrderIds = rooms.stream()
                .map(ChatRoom::getBuyOrderId)
                .filter(id -> id != null && !id.isBlank())
                .distinct().toList();
        Map<String, BuyOrder> buyOrderMap = buyOrderIds.isEmpty()
                ? Map.of()
                : buyOrderRepository.findAllById(buyOrderIds).stream()
                        .collect(Collectors.toMap(BuyOrder::getBuyOrderId, b -> b));

        // Bundle 2-A: 카드 마스터 이미지 batch 조회 (N+1 차단). null cardId/empty skip.
        // SALE 카드 + BUY 카드 cardId 합집합으로 한 번에.
        List<String> cardIds = java.util.stream.Stream.concat(
                tradeMap.values().stream().map(TradePost::getCardId),
                buyOrderMap.values().stream().map(BuyOrder::getCardId)
        ).filter(id -> id != null && !id.isBlank()).distinct().toList();
        Map<String, Card> cardMap = cardIds.isEmpty()
                ? Map.of()
                : cardRepository.findAllById(cardIds).stream()
                        .collect(Collectors.toMap(Card::getCardId, c -> c));

        return rooms.stream().map(room -> {
            String otherUserId = userId.equals(room.getBuyerUserId())
                    ? room.getSellerUserId() : room.getBuyerUserId();
            User other = userMap.get(otherUserId);
            long unread = chatMessageRepository
                    .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), userId);

            // SALE/BUY 분기 — sale_listing_id NOT NULL 이면 SALE, 아니면 BUY.
            if (room.getSaleListingId() != null) {
                TradePost trade = tradeMap.get(room.getSaleListingId());
                Card card = (trade != null && trade.getCardId() != null)
                        ? cardMap.get(trade.getCardId())
                        : null;
                String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;
                String cardName = card != null ? card.getName() : null;
                return ChatRoomDto.fromSale(room, userId,
                        trade != null ? trade.getTitle() : "",
                        trade != null ? StorageKeyUrls.firstProxyUrl(trade.getImageUrl()) : null,
                        other != null ? other.getNickname() : "",
                        other != null ? other.getProfileImageUrl() : "",
                        unread,
                        trade != null ? trade.getStatus() : null,
                        trade != null ? trade.getPrice() : null,
                        cardImageUrl, cardName);
            } else {
                BuyOrder buyOrder = buyOrderMap.get(room.getBuyOrderId());
                Card card = (buyOrder != null && buyOrder.getCardId() != null)
                        ? cardMap.get(buyOrder.getCardId())
                        : null;
                String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;
                String cardName = card != null ? card.getName() : null;
                return ChatRoomDto.fromBuy(room, userId,
                        cardName != null ? cardName : "",
                        other != null ? other.getNickname() : "",
                        other != null ? other.getProfileImageUrl() : "",
                        unread,
                        buyOrder != null ? buyOrder.getStatus() : null,
                        buyOrder != null ? buyOrder.getBidPrice() : null,
                        cardImageUrl);
            }
        }).toList();
    }

    @Override
    @Transactional
    public List<ChatMessageDto> getMessages(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, userId);
        // Phase 1: 차단 관계여도 기존 메시지 조회 가능. 입력창 비활성화는 conversation-state 응답으로.
        // 차단한 사람은 hidden_at 으로 list 미노출. 차단당한 사람은 기존 대화 유지 + canSendMessage=false.

        // Bundle 1 G1: 실제 read 갱신된 행이 있을 때만 read 이벤트 발행.
        // 이벤트는 @TransactionalEventListener(AFTER_COMMIT)로 STOMP broadcast → sender 화면 "1" 사라짐.
        int updated = chatMessageRepository.markAllAsRead(roomId, userId);
        if (updated > 0) {
            eventPublisher.publishEvent(new ChatReadEvent(roomId, userId));
        }

        Map<String, User> userMap = userRepository.findAllById(
                chatMessageRepository.findByChatRoomIdOrderByCreatedAtAsc(roomId)
                        .stream().map(ChatMessage::getSenderUserId).distinct().toList()
        ).stream().collect(Collectors.toMap(User::getUserId, u -> u));

        return chatMessageRepository.findByChatRoomIdOrderByCreatedAtAsc(roomId)
                .stream().map(msg -> {
                    User sender = userMap.get(msg.getSenderUserId());
                    return ChatMessageDto.from(msg,
                            sender != null ? sender.getNickname() : "",
                            sender != null ? sender.getProfileImageUrl() : "");
                }).toList();
    }

    /**
     * Bundle 1.5: chat_room active 상태에서 새 메시지 STOMP 수신 시 호출.
     * - 권한 체크 (room 참여자만)
     * - markAllAsRead 후 affected > 0이면 ChatReadEvent → AFTER_COMMIT broadcast
     * - 메시지 리스트 반환 X (lightweight)
     */
    @Override
    @Transactional
    public void markRoomAsRead(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        if (!userId.equals(room.getBuyerUserId()) && !userId.equals(room.getSellerUserId())) {
            throw new IllegalArgumentException("채팅방 참여자가 아닙니다.");
        }
        int updated = chatMessageRepository.markAllAsRead(roomId, userId);
        if (updated > 0) {
            eventPublisher.publishEvent(new ChatReadEvent(roomId, userId));
        }
    }

    /**
     * Bundle 2-C: 시스템 메시지 전송. sender_user_id='SYSTEM' + message_type='SYSTEM' 저장.
     * - last_message 갱신 (Codex 권장 (c) — 시간순 일관성, chat_screen 분기는 별도 polish)
     * - SystemMessageEvent publish → AFTER_COMMIT 리스너가 STOMP broadcast
     *   (commit 실패 시 메시지만 먼저 퍼지는 race 차단)
     */
    @Override
    @Transactional
    public ChatMessageDto sendSystemMessage(String roomId, String content) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));

        ChatMessage saved = chatMessageRepository.save(ChatMessage.builder()
                .chatMessageId(IdGenerator.generate())
                .chatRoomId(roomId)
                .senderUserId("SYSTEM")
                .message(content)
                .messageType("SYSTEM")
                .build());

        room.updateLastMessage(content);
        chatRoomRepository.save(room);

        // SYSTEM은 user lookup skip — ChatMessageDto.from 내부에서 nickname="시스템" 고정.
        ChatMessageDto dto = ChatMessageDto.from(saved, null, null);
        eventPublisher.publishEvent(new SystemMessageEvent(roomId, dto));
        return dto;
    }

    /**
     * Bundle 2-D: trade 상태 변경 시 해당 trade의 모든 chat_room에 시스템 메시지 fan-out.
     * TradeServiceImpl.updateStatus / completeTrade / deleteTrade에서 호출.
     * 채팅방 없으면 (아직 buyer 진입 안 함) silent — 사기 주의는 getOrCreateRoom에서 처리.
     */
    @Override
    @Transactional
    public void broadcastTradeStatusChanged(String saleListingId, String newStatus) {
        final String content = switch (newStatus) {
            case "OPEN" -> "거래가 판매 중으로 변경되었습니다.";
            case "RESERVED" -> "거래가 거래중으로 변경되었습니다.";
            case "COMPLETED" -> "거래가 완료되었습니다.";
            case "DELETED" -> "판매글이 삭제되었습니다.";
            default -> null;
        };
        if (content == null) return;
        final List<ChatRoom> rooms = chatRoomRepository.findAllBySaleListingId(saleListingId);
        for (final ChatRoom room : rooms) {
            sendSystemMessage(room.getChatRoomId(), content);
        }
    }

    /**
     * 2026-05-28 BUY chat 용 — BuyOrder 상태 변경 시 해당 BuyOrder의 모든 chat_room에 SYSTEM fan-out.
     * BuyOrderServiceImpl.cancel/markMatched 에서 호출 (Codex G).
     */
    @Override
    @Transactional
    public void broadcastBuyOrderStatusChanged(String buyOrderId, String newStatus) {
        final String content = switch (newStatus) {
            case "OPEN" -> "구매 호가가 다시 활성화되었습니다.";
            case "MATCHED" -> "구매 호가가 매칭되었습니다.";
            case "CANCELED" -> "구매 호가가 취소되었습니다.";
            default -> null;
        };
        if (content == null) return;
        final List<ChatRoom> rooms = chatRoomRepository.findAllByBuyOrderId(buyOrderId);
        for (final ChatRoom room : rooms) {
            sendSystemMessage(room.getChatRoomId(), content);
        }
    }

    // 2026-05-28 이미지 메시지 정책 상수 (Codex D — chat endpoint 한정 enforce).
    private static final long MAX_IMAGE_BYTES = 10L * 1024L * 1024L; // 10MB

    @Override
    @Transactional
    public ChatMessageDto sendImageMessage(String roomId, String senderUserId,
                                           org.springframework.web.multipart.MultipartFile file) {
        // 1. 가드 (sendMessage 동일 4종 + 파일 validation)
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, senderUserId);
        requireNotBlocked(senderUserId, otherUserOf(room, senderUserId));
        requireOtherNotLeft(room, senderUserId);
        requireNotExcludedFromActiveTrade(room);

        // 2. 파일 size 검증 (10MB) — Codex D
        if (file == null || file.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "EMPTY_FILE");
        }
        if (file.getSize() > MAX_IMAGE_BYTES) {
            throw new ResponseStatusException(HttpStatus.PAYLOAD_TOO_LARGE, "IMAGE_TOO_LARGE");
        }

        // 3. magic number 검증 — Codex C (getBytes 메모리 로딩 회피)
        final String ext;
        try {
            ext = detectImageExt(file);
        } catch (java.io.IOException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "FILE_READ_ERROR");
        }

        // 4. S3 store — chat/{roomId}/{uuid}{ext} (Codex A — uuid 추천, messageId 의존성 회피)
        final String storageKey;
        try {
            storageKey = imageStorageService.store(
                    "chat/" + roomId,
                    "image" + ext,
                    file);
        } catch (java.io.IOException e) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "S3_UPLOAD_FAILED");
        }

        // 5. DB save — message_type='IMAGE' + message=storage key
        // Codex P: S3 store 가 성공한 후에만 DB save 시도 — orphan risk 는 DB rollback 시 S3 key 남음.
        // best-effort: DB save 실패 시 S3 delete (catch 안에서). 단 트랜잭션 외부 호출이라 가능.
        ChatMessage saved;
        try {
            saved = chatMessageRepository.save(ChatMessage.builder()
                    .chatMessageId(IdGenerator.generate())
                    .chatRoomId(roomId)
                    .senderUserId(senderUserId)
                    .message(storageKey)
                    .messageType("IMAGE")
                    .build());
        } catch (RuntimeException e) {
            // best-effort cleanup
            try {
                imageStorageService.delete(storageKey);
            } catch (Exception ignored) {
                log.warn("[ChatImage] DB save 실패 후 S3 cleanup 도 실패 — orphan key={}", storageKey);
            }
            throw e;
        }

        // 6. last_message — IMAGE placeholder (정책: 채팅 list 에서 "사진" 표기)
        room.updateLastMessage("[사진]");
        chatRoomRepository.save(room);

        // 7. DTO 빌드 — ChatMessageDto.from 의 IMAGE 분기에서 key → proxy URL 변환 (Codex B)
        User sender = userRepository.findById(senderUserId).orElse(null);
        return ChatMessageDto.from(saved,
                sender != null ? sender.getNickname() : "",
                sender != null ? sender.getProfileImageUrl() : "");
    }

    /**
     * 2026-05-28 magic number sniffer — getBytes() 메모리 로딩 회피.
     * JPEG/PNG/WebP 만 허용 (Codex C). InputStream try-with 로 명시 close.
     */
    private String detectImageExt(org.springframework.web.multipart.MultipartFile file)
            throws java.io.IOException {
        byte[] h;
        try (java.io.InputStream in = file.getInputStream()) {
            h = in.readNBytes(12);
        }
        if (h.length < 4) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "FILE_TOO_SMALL");
        }
        if ((h[0] & 0xff) == 0xff && (h[1] & 0xff) == 0xd8 && (h[2] & 0xff) == 0xff) return ".jpg";
        if ((h[0] & 0xff) == 0x89 && h[1] == 0x50 && h[2] == 0x4e && h[3] == 0x47) return ".png";
        if (h.length >= 12 && h[0] == 'R' && h[1] == 'I' && h[2] == 'F' && h[3] == 'F'
                && h[8] == 'W' && h[9] == 'E' && h[10] == 'B' && h[11] == 'P') return ".webp";
        throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "UNSUPPORTED_IMAGE_TYPE");
    }

    /**
     * 2026-05-28 ImageProxyController가 chat/{roomId}/... key 요청 받았을 때 participant 검증용.
     * read-only — service-level guard 가 아닌 조회.
     *
     * <p>정책 (2026-05-28 Codex 사후 리뷰 반영):
     * <ul>
     *   <li>참여자 검증 — buyer_user_id OR seller_user_id 매칭 필수.
     *   <li>양방향 차단(block) 검증 — 한쪽이라도 차단 관계면 access 차단 ({@code requireNotBlocked} 동일 패턴).
     *   <li>{@code hidden_at} (방 나가기)은 그대로 access 허용 — 분쟁 evidence 보존 정책 (HANDOFF 5.5).
     *       방을 나가도 본인이 등록한/받은 메시지 history 는 본인 측에서 볼 권리 유지.
     * </ul>
     */
    @Override
    public boolean isRoomParticipant(String roomId, String userId) {
        return chatRoomRepository.findById(roomId)
                .map(room -> {
                    boolean isParticipant = userId.equals(room.getBuyerUserId())
                            || userId.equals(room.getSellerUserId());
                    if (!isParticipant) return false;
                    String other = otherUserOf(room, userId);
                    // 양방향 차단 — requireNotBlocked 패턴 일관 (한쪽이라도 차단 시 차단).
                    if (blockRepository.existsByBlockerIdAndBlockedId(userId, other)
                            || blockRepository.existsByBlockerIdAndBlockedId(other, userId)) {
                        return false;
                    }
                    return true;
                })
                .orElse(false);
    }

    @Override
    @Transactional
    public ChatMessageDto sendMessage(String roomId, String senderUserId, String message) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, senderUserId);
        requireNotBlocked(senderUserId, otherUserOf(room, senderUserId));
        // Phase 1 hotfix: 상대가 방을 나간 상태면 전송 차단 — "보내는 척" 금지.
        requireOtherNotLeft(room, senderUserId);
        // 거래중 모델: 비선택 buyer 메시지 전송 차단. 판매자/선택 상대만 통과.
        requireNotExcludedFromActiveTrade(room);

        ChatMessage saved = chatMessageRepository.save(ChatMessage.builder()
                .chatMessageId(IdGenerator.generate())
                .chatRoomId(roomId)
                .senderUserId(senderUserId)
                .message(message)
                .build());

        room.updateLastMessage(message);
        chatRoomRepository.save(room);

        User sender = userRepository.findById(senderUserId).orElse(null);
        return ChatMessageDto.from(saved,
                sender != null ? sender.getNickname() : "",
                sender != null ? sender.getProfileImageUrl() : "");
    }

    /**
     * Phase 1 hotfix: 채팅방 나가기 — 본인 hidden_at set + 상대방에게 SYSTEM 메시지.
     * 상대방은 방 유지 + 안내 + 입력 비활성화. 재초대는 getOrCreateRoom 가드로 차단.
     */
    @Override
    @Transactional
    public void leaveRoom(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, userId);
        room.hideForUser(userId);
        chatRoomRepository.save(room);
        // 상대방에게 1회 안내. AFTER_COMMIT STOMP broadcast로 즉시 갱신.
        sendSystemMessage(roomId, "상대방이 채팅방을 나갔습니다.");
    }

    /**
     * Phase 1 hotfix: 입력창/안내 상태. 우선순위 — 차단(내가/상대) → 상대 나감.
     * canSendMessage=false 조건 = 내가 차단 OR 상대가 차단 OR 상대가 방 나감.
     */
    @Override
    public ConversationStateDto getConversationState(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, userId);
        String other = otherUserOf(room, userId);
        boolean iBlocked = blockRepository.existsByBlockerIdAndBlockedId(userId, other);
        boolean blockedByOther = blockRepository.existsByBlockerIdAndBlockedId(other, userId);
        boolean otherLeft = isOtherLeft(room, userId);
        // 거래중 모델: TradePost.activeChatRoomId 가 NOT NULL 이고 현재 room 이 아니면
        // 비선택 buyer → 입력 비활성 + 안내. 판매자/선택된 buyer 는 그대로 채팅 가능.
        // TradePost 한 번 조회 — activeChatRoomId 체크 + COMPLETED 분기 (완료 후 안내 문구 별도).
        // 2026-05-28: BUY chat (sale_listing_id == null) 은 active trade 모델 적용 X (Codex L).
        TradePost trade = room.getSaleListingId() != null
                ? tradePostRepository.findById(room.getSaleListingId()).orElse(null)
                : null;
        String activeChatRoomId = trade != null ? trade.getActiveChatRoomId() : null;
        boolean isExcludedFromActiveTrade = activeChatRoomId != null
                && !activeChatRoomId.equals(room.getChatRoomId());
        boolean tradeCompleted = trade != null && "COMPLETED".equals(trade.getStatus());
        boolean canSend = !iBlocked && !blockedByOther && !otherLeft && !isExcludedFromActiveTrade;
        String notice;
        if (iBlocked) {
            notice = "차단한 사용자입니다. 차단을 해제하면 대화할 수 있어요.";
        } else if (blockedByOther) {
            notice = "상대방의 설정으로 인해 더 이상 대화할 수 없습니다.";
        } else if (otherLeft) {
            notice = "상대방이 채팅방을 나갔습니다.";
        } else if (isExcludedFromActiveTrade) {
            notice = tradeCompleted
                    ? "거래가 완료된 판매글입니다."
                    : "다른 사용자와 거래가 진행 중입니다.";
        } else {
            notice = null;
        }
        return new ConversationStateDto(canSend, notice, iBlocked, blockedByOther, otherLeft, isExcludedFromActiveTrade);
    }

    /**
     * Phase 1 hotfix#5: 차단 액션 hook — silent state event (visible 메시지 X).
     * 이유: 차단 상태는 채팅 메시지가 아니라 conversation-state. visible SYSTEM 으로
     *       남기면 (1) DB 메시지로 영구 저장되어 현재 상태(unblock 후)와 충돌
     *       (2) 양쪽 banner 가 이미 동일 상태 안내. 중복 누적 + 거짓 안내 위험.
     * 처리: publishStateChangedEvent 만 호출 → 양쪽 클라가 conversation-state 재조회.
     * notifyUnblock 과 통일된 silent pattern.
     */
    @Override
    @Transactional
    public void notifyBlock(String blockerId, String blockedId) {
        List<ChatRoom> rooms = chatRoomRepository.findAllBetweenUsers(blockerId, blockedId);
        for (ChatRoom room : rooms) {
            publishStateChangedEvent(room.getChatRoomId());
        }
    }

    /**
     * Phase 1 hotfix#4: 차단 해제 hook — silent state event (visible 메시지 X).
     * 이유: mutual block 상태에서 한쪽만 해제해도 "다시 대화할 수 있어요" 거짓 안내
     *       위험 + 채팅에 mutation 말풍선 누적되는 UX 어색.
     * 처리: ChatMessageDto with messageType="STATE_CHANGED" (DB 저장 X) → SystemMessageEvent
     *       publish → AFTER_COMMIT STOMP broadcast → 클라가 messageType 분기해서
     *       list 추가 안 하고 _loadConversationState()만 재호출.
     * 결과: 양쪽 banner / 입력 / 메뉴 label 모두 ConversationStateDto 단일 진실원으로 갱신.
     */
    @Override
    @Transactional
    public void notifyUnblock(String blockerId, String unblockedId) {
        List<ChatRoom> rooms = chatRoomRepository.findAllBetweenUsers(blockerId, unblockedId);
        for (ChatRoom room : rooms) {
            publishStateChangedEvent(room.getChatRoomId());
        }
    }

    /**
     * Phase 1 hotfix#4: state-only event — DB 저장 없이 STOMP broadcast 만.
     * messageType="STATE_CHANGED" 페이로드. 클라 분기로 채팅 list 비추가.
     * SystemMessageEvent listener (AFTER_COMMIT)가 동일 topic 으로 broadcast.
     */
    private void publishStateChangedEvent(String roomId) {
        ChatMessageDto payload = ChatMessageDto.builder()
                .chatMessageId(IdGenerator.generate())
                .chatRoomId(roomId)
                .senderUserId("SYSTEM")
                .message("")
                .messageType("STATE_CHANGED")
                .build();
        eventPublisher.publishEvent(new SystemMessageEvent(roomId, payload));
    }

    /** room 양쪽 user 중 인자 userId 가 아닌 쪽. block check 대상 산출용. */
    private String otherUserOf(ChatRoom room, String userId) {
        return userId.equals(room.getBuyerUserId())
                ? room.getSellerUserId() : room.getBuyerUserId();
    }

    /** room 참여자 검증 — buyer/seller 둘 다 아니면 403. URL/push 직접 진입 차단. */
    private void requireParticipant(ChatRoom room, String userId) {
        if (!userId.equals(room.getBuyerUserId()) && !userId.equals(room.getSellerUserId())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "NOT_PARTICIPANT");
        }
    }

    /** 양방향 차단 검증 — 한쪽이라도 차단 관계면 403. getOrCreateRoom / sendMessage / getMessages 공통. */
    private void requireNotBlocked(String userA, String userB) {
        if (blockRepository.existsByBlockerIdAndBlockedId(userA, userB)
                || blockRepository.existsByBlockerIdAndBlockedId(userB, userA)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "BLOCKED");
        }
    }

    /** Phase 1 hotfix: 상대가 방을 나간 상태인지. canSendMessage / sendMessage 가드 공통. */
    private boolean isOtherLeft(ChatRoom room, String userId) {
        return userId.equals(room.getBuyerUserId())
                ? room.getSellerHiddenAt() != null
                : room.getBuyerHiddenAt() != null;
    }

    /** Phase 1 hotfix: 상대 나간 방에 메시지 전송 차단 — "보내는 척" 금지. */
    private void requireOtherNotLeft(ChatRoom room, String userId) {
        if (isOtherLeft(room, userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "OTHER_LEFT");
        }
    }

    /**
     * 거래중 모델: room 의 TradePost.activeChatRoomId 가 NOT NULL 이고 현재 room 이
     * 아닌 경우 비선택 buyer. trade 못 찾으면 (race) 안전 차원 false (안 막음).
     *
     * <p>2026-05-28: BUY chat (sale_listing_id == null) 은 active trade 모델 적용 X — short-circuit
     * false. BuyOrder 도메인은 1:1 매칭 단일 채팅 가정이 없음 (Codex L 지적). TradePost lookup 시도 시
     * IllegalArgumentException 방지.</p>
     */
    private boolean isExcludedFromActiveTrade(ChatRoom room) {
        if (room.getSaleListingId() == null) {
            return false;
        }
        return tradePostRepository.findById(room.getSaleListingId())
                .map(trade -> {
                    String active = trade.getActiveChatRoomId();
                    return active != null && !active.equals(room.getChatRoomId());
                })
                .orElse(false);
    }

    /** 거래중 모델: 비선택 buyer 가 메시지 전송 시 403. 판매자/선택 상대만 통과. */
    private void requireNotExcludedFromActiveTrade(ChatRoom room) {
        if (isExcludedFromActiveTrade(room)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "EXCLUDED_FROM_ACTIVE_TRADE");
        }
    }
}
