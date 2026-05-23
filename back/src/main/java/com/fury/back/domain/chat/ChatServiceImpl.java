package com.fury.back.domain.chat;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ConversationStateDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.chat.event.ChatReadEvent;
import com.fury.back.domain.chat.event.SystemMessageEvent;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import com.fury.back.storage.CardCdnUrls;
import com.fury.back.storage.StorageKeyUrls;
import lombok.RequiredArgsConstructor;
import org.springframework.context.ApplicationEventPublisher;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ChatServiceImpl implements ChatService {

    private final ChatRoomRepository chatRoomRepository;
    private final ChatMessageRepository chatMessageRepository;
    private final TradePostRepository tradePostRepository;
    private final UserRepository userRepository;
    private final ApplicationEventPublisher eventPublisher;
    // Bundle 2-A: 거래 미니카드용 카드 마스터 이미지 조립 (#62 CardCdnUrls 재활용).
    private final CardRepository cardRepository;
    private final CardCdnUrls cardCdnUrls;
    private final BlockRepository blockRepository;

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
                        throw new IllegalStateException(switch (trade.getStatus()) {
                            case "RESERVED" -> "예약 중인 거래입니다.";
                            case "COMPLETED" -> "거래가 완료되었습니다.";
                            case "DELETED" -> "삭제된 거래입니다.";
                            default -> "현재 거래 상태에서는 채팅을 시작할 수 없습니다.";
                        });
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
        }

        User other = userRepository.findById(trade.getSellerId()).orElse(null);
        long unread = chatMessageRepository
                .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), buyerUserId);

        // Bundle 2-A: 카드 마스터 이미지 조립. card 매칭 부재 시 null (프론트 placeholder).
        Card card = trade.getCardId() != null
                ? cardRepository.findById(trade.getCardId()).orElse(null)
                : null;
        String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;

        return ChatRoomDto.from(room, buyerUserId,
                trade.getTitle(), StorageKeyUrls.firstProxyUrl(trade.getImageUrl()),
                other != null ? other.getNickname() : "",
                other != null ? other.getProfileImageUrl() : "",
                unread,
                trade.getStatus(), trade.getPrice(), cardImageUrl);
    }

    @Override
    public List<ChatRoomDto> getMyRooms(String userId) {
        List<String> blockedUserIds = blockRepository.findAllByBlockerId(userId).stream()
                .map(Block::getBlockedId)
                .distinct()
                .toList();
        List<ChatRoom> rooms = chatRoomRepository.findMyRooms(userId).stream()
                .filter(room -> {
                    String otherUserId = userId.equals(room.getBuyerUserId())
                            ? room.getSellerUserId() : room.getBuyerUserId();
                    return !blockedUserIds.contains(otherUserId);
                })
                .toList();

        // 필요한 userId 수집
        List<String> userIds = rooms.stream()
                .flatMap(r -> java.util.stream.Stream.of(r.getBuyerUserId(), r.getSellerUserId()))
                .distinct().toList();
        Map<String, User> userMap = userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u));

        List<String> tradeIds = rooms.stream().map(ChatRoom::getSaleListingId).distinct().toList();
        Map<String, TradePost> tradeMap = tradePostRepository.findAllById(tradeIds).stream()
                .collect(Collectors.toMap(TradePost::getTradeId, t -> t));

        // Bundle 2-A: 카드 마스터 이미지 batch 조회 (N+1 차단). null cardId/empty skip.
        List<String> cardIds = tradeMap.values().stream()
                .map(TradePost::getCardId)
                .filter(id -> id != null && !id.isBlank())
                .distinct().toList();
        Map<String, Card> cardMap = cardIds.isEmpty()
                ? Map.of()
                : cardRepository.findAllById(cardIds).stream()
                        .collect(Collectors.toMap(Card::getCardId, c -> c));

        return rooms.stream().map(room -> {
            String otherUserId = userId.equals(room.getBuyerUserId())
                    ? room.getSellerUserId() : room.getBuyerUserId();
            User other = userMap.get(otherUserId);
            TradePost trade = tradeMap.get(room.getSaleListingId());
            Card card = (trade != null && trade.getCardId() != null)
                    ? cardMap.get(trade.getCardId())
                    : null;
            String cardImageUrl = card != null ? cardCdnUrls.forCard(card) : null;
            long unread = chatMessageRepository
                    .countByChatRoomIdAndIsReadFalseAndSenderUserIdNot(room.getChatRoomId(), userId);
            return ChatRoomDto.from(room, userId,
                    trade != null ? trade.getTitle() : "",
                    trade != null ? StorageKeyUrls.firstProxyUrl(trade.getImageUrl()) : null,
                    other != null ? other.getNickname() : "",
                    other != null ? other.getProfileImageUrl() : "",
                    unread,
                    trade != null ? trade.getStatus() : null,
                    trade != null ? trade.getPrice() : null,
                    cardImageUrl);
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
            case "RESERVED" -> "거래가 예약 중으로 변경되었습니다.";
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

    @Override
    @Transactional
    public ChatMessageDto sendMessage(String roomId, String senderUserId, String message) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, senderUserId);
        requireNotBlocked(senderUserId, otherUserOf(room, senderUserId));

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
     * Phase 1: 채팅방 나가기 — 본인의 hidden_at set.
     * DB 보존, list 미노출. 차단/관리자 조회와 동일 모델.
     */
    @Override
    @Transactional
    public void leaveRoom(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, userId);
        room.hideForUser(userId);
        chatRoomRepository.save(room);
    }

    /**
     * Phase 1: 채팅방 입력창/안내 상태 조회. 양방향 차단 관계 산출 → canSendMessage + blockNotice.
     * 클라가 진입 시 호출. 입력 비활성화 + 안내 banner UX 의 단일 진실원.
     */
    @Override
    public ConversationStateDto getConversationState(String roomId, String userId) {
        ChatRoom room = chatRoomRepository.findById(roomId)
                .orElseThrow(() -> new IllegalArgumentException("채팅방 없음: " + roomId));
        requireParticipant(room, userId);
        String other = otherUserOf(room, userId);
        boolean iBlocked = blockRepository.existsByBlockerIdAndBlockedId(userId, other);
        boolean blockedByOther = blockRepository.existsByBlockerIdAndBlockedId(other, userId);
        boolean canSend = !iBlocked && !blockedByOther;
        String notice = null;
        if (blockedByOther) {
            notice = "상대방의 설정으로 인해 더 이상 대화할 수 없습니다.";
        } else if (iBlocked) {
            notice = "차단한 사용자입니다. 차단을 해제하면 대화할 수 있어요.";
        }
        return new ConversationStateDto(canSend, notice);
    }

    /**
     * Phase 1: 차단 액션 hook (BlockController 가 차단 저장 후 호출).
     * - 두 user 사이 모든 방 조회
     * - 차단한 사람 hidden_at set (차단당한 사람은 그대로 — 정책)
     * - 각 방에 "상대방의 설정으로 인해 더 이상 대화할 수 없습니다." SYSTEM 메시지 1회
     *   → AFTER_COMMIT STOMP broadcast 로 차단당한 사람 화면 즉시 갱신
     */
    @Override
    @Transactional
    public void notifyBlock(String blockerId, String blockedId) {
        List<ChatRoom> rooms = chatRoomRepository.findAllBetweenUsers(blockerId, blockedId);
        for (ChatRoom room : rooms) {
            room.hideForUser(blockerId);
            chatRoomRepository.save(room);
            sendSystemMessage(room.getChatRoomId(),
                    "상대방의 설정으로 인해 더 이상 대화할 수 없습니다.");
        }
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
}
